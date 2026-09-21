#include <metal_stdlib>
using namespace metal;

struct GlassUniforms {
    float4 optical; // thickness, relief, pitch (m), IOR
    float4 surface; // exponent, edge amplitude (m), edge width, micro height (m)
    float4 scene;   // glass distance, constant scene Z, tan(vertical FOV / 2), aspect
    float4 light;   // environment exposure, yaw, reserved
    uint4 flags;   // fixed seed, diagnostic, pattern (quadra/cross large/diamond), reserved
};

uint hash32(uint x) {
    x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; return x ^ (x >> 16);
}
float randomSigned(uint x) { return float(hash32(x) & 0x00ffffffu) / 8388607.5 - 1.0; }
float smoother(float x) { return x*x*x*(x*(x*6.0-15.0)+10.0); }
float smootherDerivative(float x) { return 30.0*x*x*(x-1.0)*(x-1.0); }
struct Surface { float height; float2 gradient; };

struct AxisWeights { float4 value; float4 derivative; };

// Round a piecewise-linear profile only near its vertices. At a join the slope
// is the mean of both neighboring facets, rather than an artificial zero that
// inserts a thin, almost-unrefracted copy of the scene along every grid line.
AxisWeights rolledWeights(float t, float width) {
    float4 value=float4(0,1.0-t,t,0), derivative=float4(0,-1,1,0);
    if (t < width) {
        float z=(t+width)/(2.0*width);
        value += (2.0*width*(z*z*z-0.5*z*z*z*z)-t)*float4(1,-2,1,0);
        derivative += (z*z*(3.0-2.0*z)-1.0)*float4(1,-2,1,0);
    } else if (t > 1.0-width) {
        float z=(t-1.0+width)/(2.0*width);
        value += (2.0*width*(z*z*z-0.5*z*z*z*z))*float4(0,1,-2,1);
        derivative += (z*z*(3.0-2.0*z))*float4(0,1,-2,1);
    }
    return {value,derivative};
}
float vertexHeight(int2 id, constant GlassUniforms &u) {
    if (u.flags.z == 1) {
        // Cross Large: broad crossed ribs with regular alternating facets.
        // Each axis repeats every two facets; joins share the rounded profile.
        float2 rib=float2((id.x & 1) ? 1.0 : -1.0,(id.y & 1) ? 1.0 : -1.0);
        return u.optical.y*(0.5+0.38*(rib.x+rib.y));
    }
    uint seed=hash32(as_type<uint>(id.x)^hash32(as_type<uint>(id.y))^u.flags.x);
    // Rolled horizontal/vertical ridges dominate; a small cross term avoids a
    // perfectly separable lattice. This keeps broad cell interiors nearly planar
    // instead of turning every four vertices into an obvious saddle lens.
    float column=randomSigned(as_type<uint>(id.x)^u.flags.x);
    float row=randomSigned(as_type<uint>(id.y)^hash32(u.flags.x));
    return u.optical.y * (0.5+0.72*column+0.72*row+0.05*randomSigned(seed));
}

// A tensor-product rolled plate, selected against the reference's broad facets.
// Heights (not UV offsets) are varied; normals and both rays derive from them.
Surface quadraSurfaceAt(float2 p, constant GlassUniforms &u) {
    float2 cell=p/u.optical.z+float2(0.19,0.37);
    int2 id=int2(floor(cell));
    float2 q=fract(cell);
    // Keep a broad facet, but give its join enough width to avoid a pinched seam.
    float shoulder=mix(0.26,0.12,(u.surface.x-2.0)/6.0);
    AxisWeights x=rolledWeights(q.x,shoulder), y=rolledWeights(q.y,shoulder);
    float height=0;
    float2 gradient=0;
    for (int j=0; j<4; j++) {
        if (y.value[j]==0 && y.derivative[j]==0) continue;
        for (int i=0; i<4; i++) {
            if (x.value[i]==0 && x.derivative[i]==0) continue;
            float h=vertexHeight(id+int2(i-1,j-1),u);
            height += h*x.value[i]*y.value[j];
            gradient += h*float2(x.derivative[i]*y.value[j],x.value[i]*y.derivative[j])/u.optical.z;
        }
    }
    // A shallow, smoothly joined crown changes local magnification: a feature
    // can fill a cell while its neighbor samples a different part of the scene.
    float2 centered=q-0.5;
    float2 dome=1.0-4.0*centered*centered;
    float crown=u.optical.y*0.065;
    height += crown*dome.x*dome.x*dome.y*dome.y;
    gradient += -16.0*crown*centered*float2(dome.x*dome.y*dome.y,dome.y*dome.x*dome.x)/u.optical.z;
    float2 b=clamp(min(q,1.0-q)/u.surface.z,0.0,1.0);
    float2 db=select(float2(1),float2(-1),q>0.5)/u.surface.z;
    float2 S=float2(smoother(b.x),smoother(b.y));
    float2 dS=float2(smootherDerivative(b.x),smootherDerivative(b.y))*db;
    height += u.surface.y*S.x*S.y;
    gradient += u.surface.y*float2(dS.x*S.y,S.x*dS.y)/u.optical.z;
    float2 f=float2(4100.0,5300.0), wave=p*f+float(u.flags.x%1024u)*0.01;
    height += u.surface.w*sin(wave.x)*sin(wave.y);
    gradient += u.surface.w*f*float2(cos(wave.x)*sin(wave.y),sin(wave.x)*cos(wave.y));
    return {height,gradient};
}

Surface surfaceAt(float2 p, constant GlassUniforms &u) {
    if (u.flags.z == 2) {
        // Rotate the glass geometry, including normals, without rotating the scene.
        const float c=0.70710678118;
        Surface s=quadraSurfaceAt(float2(p.x+p.y,p.y-p.x)*c,u);
        s.gradient=float2(s.gradient.x-s.gradient.y,s.gradient.x+s.gradient.y)*c;
        return s;
    }
    return quadraSurfaceAt(p,u);
}

float fresnel(float3 incident, float3 normal, float n1, float n2) {
    float ci = clamp(-dot(incident, normal), 0.0, 1.0);
    float st2 = (n1/n2)*(n1/n2)*(1.0-ci*ci);
    if (st2 >= 1.0) return 1.0;
    float ct = sqrt(max(0.0, 1.0-st2));
    float rs = (n1*ci-n2*ct)/max(n1*ci+n2*ct, 1e-8);
    float rp = (n2*ci-n1*ct)/max(n2*ci+n1*ct, 1e-8);
    return 0.5*(rs*rs+rp*rp);
}

// An explicitly synthetic camera-side room environment. Highlights are evaluated
// from reflected ray directions, including the patterned back interface.
float3 environment(float3 ray, constant GlassUniforms &u) {
    float c = cos(u.light.y), s = sin(u.light.y);
    ray = float3(c*ray.x+s*ray.z, ray.y, -s*ray.x+c*ray.z);
    float2 e = ray.xy / max(abs(ray.z), 0.15);
    float haze = exp(-dot((e-float2(0.45,-0.1))*float2(0.65,0.8),
                         (e-float2(0.45,-0.1))*float2(0.65,0.8)));
    float panel=0.0;
    for (int i=0; i<5; i++) {
        float2 d=(e-float2(-0.64+float(i)*0.14,-0.55))/float2(0.027,0.22);
        panel += exp(-dot(d,d));
    }
    float2 broad=(e-float2(0.35,-0.3))/float2(0.65,0.85);
    float fill=exp(-dot(broad,broad));
    return u.light.x * (float3(0.26,0.28,0.3)*haze + float3(7.0,7.1,7.2)*panel + 0.8*fill);
}

kernel void buildGlassMap(texture2d<float, access::write> map [[texture(0)]],
                          texture2d<float, access::write> lighting [[texture(1)]],
                          constant GlassUniforms &u [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= map.get_width() || gid.y >= map.get_height()) return;
    float2 size = float2(map.get_width(),map.get_height());
    float2 uv = (float2(gid)+0.5)/size;
    float2 projection = float2(u.scene.z*u.scene.w, u.scene.z)*2.0;
    float3 incident = normalize(float3((uv-0.5)*projection,1.0));
    float3 p1 = incident*(u.scene.x/incident.z);
    float eta = u.optical.w/1.0003;
    float3 inside = refract(incident, float3(0,0,-1), 1.0/eta);

    // Bound the root, then use safeguarded Newton. The supported small-relief
    // material has a forward first intersection; pathological steep sliders are
    // still finite and receive an explicit diagnostic fallback.
    float lower = max(0.000001,(u.optical.x-u.optical.y-2.0*u.surface.w)/inside.z);
    float upper = (u.optical.x+u.optical.y*2.06+2.0*u.surface.y+2.0*u.surface.w)/inside.z;
    float distance = (lower+upper)*0.5;
    Surface surf;
    float residual = 0;
    for (int i=0; i<14; i++) {
        float3 point = p1 + inside*distance;
        surf = surfaceAt(point.xy,u);
        residual = point.z-u.scene.x-u.optical.x-surf.height;
        if (abs(residual) < 1e-8) break;
        if (residual > 0) upper=distance; else lower=distance;
        float derivative = inside.z-dot(surf.gradient,inside.xy);
        float candidate = distance-residual/(abs(derivative)>1e-6 ? derivative : 1e-6);
        distance = candidate>lower && candidate<upper ? candidate : (lower+upper)*0.5;
    }
    float3 p2 = p1 + inside*distance;
    surf = surfaceAt(p2.xy,u);
    float3 backNormal = normalize(float3(surf.gradient,-1));
    float3 outgoing = refract(inside,backNormal,eta);
    float F1 = fresnel(incident,float3(0,0,-1),1.0003,u.optical.w);
    float F2 = fresnel(inside,backNormal,u.optical.w,1.0003);
    bool invalid = outgoing.z <= 0.001 || abs(residual) > 0.00002;
    float2 sampleUV = uv;
    if (!invalid) {
        float3 hit = p2+outgoing*((u.scene.y-p2.z)/outgoing.z);
        sampleUV = hit.xy/(u.scene.y*projection)+0.5;
    }
    float3 reflectionDirection = reflect(inside,backNormal);
    reflectionDirection = refract(reflectionDirection,float3(0,0,1),eta);
    float3 frontReflection = environment(reflect(incident,float3(0,0,-1)),u);
    float3 backReflection = environment(reflectionDirection,u);
    float transmission = invalid ? 0.0 : (1.0-F1)*(1.0-F2);
    float3 reflection = F1*frontReflection + (1.0-F1)*(1.0-F1)*F2*backReflection;
    if (invalid) reflection = frontReflection;
    float outside = any(sampleUV < 0.0) || any(sampleUV > 1.0) ? 1.0 : 0.0;
    // Keep unsupported edge content bounded; do not invent missing scene pixels.
    sampleUV = clamp(sampleUV,float2(0.0001),float2(0.9999));
    map.write(float4(sampleUV, outside, invalid ? 1.0 : 0.0),gid);
    lighting.write(float4(reflection,transmission),gid);
    if (u.flags.y == 1) lighting.write(float4(surf.gradient*0.5+0.5,surf.height/max(u.optical.y,1e-8),1),gid);
}

kernel void probeSurface(device const float2 *positions [[buffer(0)]],
                         device float4 *results [[buffer(1)]],
                         constant GlassUniforms &u [[buffer(2)]],
                         uint gid [[thread_position_in_grid]]) {
    Surface s=surfaceAt(positions[gid],u);
    results[gid]=float4(s.height,s.gradient,0);
}

float3 toSRGB(float3 x) {
    x = max(x,0.0);
    return select(1.055*pow(x,float3(1.0/2.4))-0.055,12.92*x,x<=0.0031308);
}

kernel void applyGlass(texture2d<float, access::sample> source [[texture(0)]],
                       texture2d<float, access::read> map [[texture(1)]],
                       texture2d<float, access::read> lighting [[texture(2)]],
                       texture2d<float, access::write> output [[texture(3)]],
                       constant uint &mode [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    constexpr sampler sampleFilter(coord::normalized, address::clamp_to_edge,
                                   filter::linear, mip_filter::linear, max_anisotropy(8));
    float2 size = float2(output.get_width(),output.get_height());
    float2 uv = (float2(gid)+0.5)/size;
    float4 m = map.read(gid);
    float4 light = lighting.read(gid);
    float3 color;
    if (mode == 1) color = source.sample(sampleFilter,uv,level(0)).rgb;
    else if (mode == 2) color = float3(m.z,m.w,0);
    else if (mode == 3) color = light.rgb;
    else {
        // A seam can compress many source pixels into one output pixel. Use the
        // full footprint with hardware anisotropic mip filtering; five taps with
        // an eight-pixel cap aliased detail into chewed, repeated strips.
        uint2 left = uint2(gid.x > 0 ? gid.x-1 : 0,gid.y);
        uint2 up = uint2(gid.x,gid.y > 0 ? gid.y-1 : 0);
        uint2 right = uint2(min(gid.x+1,output.get_width()-1),gid.y);
        uint2 down = uint2(gid.x,min(gid.y+1,output.get_height()-1));
        float2 dx = map.read(right).xy-m.xy, bx=m.xy-map.read(left).xy;
        float2 dy = map.read(down).xy-m.xy, by=m.xy-map.read(up).xy;
        // Retain the larger one-sided footprint at a fold; averaging cancels it.
        if (dot(bx,bx)>dot(dx,dx)) dx=bx;
        if (dot(by,by)>dot(dy,dy)) dy=by;
        color = source.sample(sampleFilter,m.xy,gradient2d(dx,dy)).rgb;
        color = color*light.a + light.rgb;
    }
    output.write(float4(toSRGB(color),1.0),gid);
}
