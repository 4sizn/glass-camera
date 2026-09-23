#!/usr/bin/env python3
"""Generate the dependency-free Xcode project using a standard plist."""
from pathlib import Path
import hashlib
import plistlib

ROOT = Path(__file__).resolve().parent.parent
objects = {}

def obj(label, **value):
    key = hashlib.sha1(label.encode()).hexdigest()[:24].upper()
    objects[key] = value
    return key

def files(paths, build=True):
    refs, builds = [], []
    for path in paths:
        kind = "sourcecode.swift" if path.endswith(".swift") else "folder.assetcatalog" if path.endswith(".xcassets") else "text"
        ref = obj(path, isa="PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="<group>")
        refs.append(ref)
        if build: builds.append(obj("build:"+path, isa="PBXBuildFile", fileRef=ref))
    return refs, builds

swift = sorted(str(p.relative_to(ROOT)) for p in (ROOT/"QuadraCamera").glob("*.swift"))
resources = sorted(str(p.relative_to(ROOT)) for p in (ROOT/"QuadraCamera/Resources").glob("*"))
resources += ["QuadraCamera/Shaders/Quadra.metal", "QuadraCamera/Assets.xcassets"]
source_refs, source_builds = files(swift)
resource_refs, resource_builds = files(resources)
info_refs, _ = files(["QuadraCamera/Info.plist"],False)
product = obj("app-product",isa="PBXFileReference",explicitFileType="wrapper.application",path="QUADRA.app",sourceTree="BUILT_PRODUCTS_DIR")
tests_product = obj("tests-product",isa="PBXFileReference",explicitFileType="wrapper.cfbundle",path="QuadraUITests.xctest",sourceTree="BUILT_PRODUCTS_DIR")
test_refs, test_builds = files(["Tests/QuadraUITests.swift"])
products = obj("products",isa="PBXGroup",children=[product,tests_product],name="Products",sourceTree="<group>")
group = obj("main-group",isa="PBXGroup",children=source_refs+resource_refs+info_refs+test_refs+[products],sourceTree="<group>")

def configs(name, settings):
    refs = []
    for mode in ["Debug","Release"]:
        values = dict(settings)
        values.update({"SWIFT_OPTIMIZATION_LEVEL":"-Onone" if mode=="Debug" else "-O", "DEBUG_INFORMATION_FORMAT":"dwarf"})
        if mode == "Debug": values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]="DEBUG"
        refs.append(obj(name+mode,isa="XCBuildConfiguration",name=mode,buildSettings=values))
    return obj(name+"configs",isa="XCConfigurationList",buildConfigurations=refs,defaultConfigurationIsVisible=0,defaultConfigurationName="Release")

common = {"SDKROOT":"iphoneos","IPHONEOS_DEPLOYMENT_TARGET":"17.0","SWIFT_VERSION":"5.0", "CLANG_ENABLE_MODULES":"YES","TARGETED_DEVICE_FAMILY":"1","CODE_SIGN_STYLE":"Automatic"}
app_settings = dict(common, PRODUCT_BUNDLE_IDENTIFIER="com.lotus.quadraglass",PRODUCT_NAME="QUADRA",INFOPLIST_FILE="QuadraCamera/Info.plist",DEVELOPMENT_TEAM="VN497S6KK3",SUPPORTED_PLATFORMS="iphoneos iphonesimulator",ENABLE_USER_SCRIPT_SANDBOXING="YES",SWIFT_EMIT_LOC_STRINGS="NO",ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon")
source_phase=obj("sources",isa="PBXSourcesBuildPhase",buildActionMask=2147483647,files=source_builds,runOnlyForDeploymentPostprocessing=0)
resource_phase=obj("resources",isa="PBXResourcesBuildPhase",buildActionMask=2147483647,files=resource_builds,runOnlyForDeploymentPostprocessing=0)
app=obj("app-target",isa="PBXNativeTarget",buildConfigurationList=configs("app",app_settings),buildPhases=[source_phase,resource_phase],buildRules=[],dependencies=[],name="QUADRA",productName="QUADRA",productReference=product,productType="com.apple.product-type.application")
project_key=hashlib.sha1(b"project").hexdigest()[:24].upper()
proxy=obj("test-proxy",isa="PBXContainerItemProxy",containerPortal=project_key,proxyType=1,remoteGlobalIDString=app,remoteInfo="QUADRA")
dependency=obj("test-dependency",isa="PBXTargetDependency",target=app,targetProxy=proxy)
test_phase=obj("test-sources",isa="PBXSourcesBuildPhase",buildActionMask=2147483647,files=test_builds,runOnlyForDeploymentPostprocessing=0)
test_settings=dict(common,PRODUCT_BUNDLE_IDENTIFIER="com.lotus.quadraglass.uitests",PRODUCT_NAME="QuadraUITests",GENERATE_INFOPLIST_FILE="YES",TEST_TARGET_NAME="QUADRA",DEVELOPMENT_TEAM="VN497S6KK3")
tests=obj("tests-target",isa="PBXNativeTarget",buildConfigurationList=configs("tests",test_settings),buildPhases=[test_phase],buildRules=[],dependencies=[dependency],name="QuadraUITests",productName="QuadraUITests",productReference=tests_product,productType="com.apple.product-type.bundle.ui-testing")
obj("project",isa="PBXProject",attributes={"LastUpgradeCheck":"2600","TargetAttributes":{app:{"CreatedOnToolsVersion":"26.0"},tests:{"CreatedOnToolsVersion":"26.0","TestTargetID":app}}},buildConfigurationList=configs("project",{}),compatibilityVersion="Xcode 14.0",developmentRegion="ko",knownRegions=["ko","en","Base"],mainGroup=group,productRefGroup=products,projectDirPath="",projectRoot="",targets=[app,tests])
directory=ROOT/"QUADRA.xcodeproj"
directory.mkdir(exist_ok=True)
with (directory/"project.pbxproj").open("wb") as f:
    plistlib.dump({"archiveVersion":"1","classes":{},"objectVersion":"56","objects":objects,"rootObject":project_key},f,sort_keys=False)
schemes=directory/"xcshareddata/xcschemes"
schemes.mkdir(parents=True,exist_ok=True)
def reference(target, product):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{product.split(".")[0]}" ReferencedContainer="container:QUADRA.xcodeproj"/>'
(schemes/"QUADRA.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(app,"QUADRA.app")}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO">{reference(tests,"QuadraUITests.xctest")}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app,"QUADRA.app")}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app,"QUADRA.app")}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(directory)
