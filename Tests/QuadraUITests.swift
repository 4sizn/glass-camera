import XCTest
import UIKit

final class QuadraUITests: XCTestCase {
    @MainActor func testPatternsSelectionPersistenceAndCapture() throws {
        let app=XCUIApplication()
        app.launchArguments=["--sample"]
        app.launch()
        XCTAssertTrue(app.buttons["reset-controls"].waitForExistence(timeout: 15))
        app.buttons["reset-controls"].tap()
        let preview=app.descendants(matching: .any).matching(identifier: "camera-preview").firstMatch
        let frame=preview.frame
        let initialValue=dial(in: app).value as? String
        for pattern in ["crossLarge","diamond"] {
            let button=app.buttons["pattern-\(pattern)"]
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.minY,preview.frame.maxY)
            button.tap()
            XCTAssertTrue(button.isSelected)
            XCTAssertEqual(dial(in: app).value as? String,initialValue)
            XCTAssertEqual(preview.frame,frame)
            sleep(1)
            let shot=XCTAttachment(screenshot: app.screenshot())
            shot.name="pattern-\(pattern)-preview"; shot.lifetime = .keepAlways; add(shot)
            app.buttons["shutter"].tap()
            XCTAssertTrue(app.staticTexts["사진 앱에 저장했어요"].waitForExistence(timeout: 30))
        }
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["pattern-diamond"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["pattern-diamond"].isSelected,"Pattern selection was not restored")
        XCTAssertEqual(dial(in: app).value as? String,initialValue)
        app.buttons["compare"].tap()
        app.buttons["pattern-crossLarge"].tap()
        XCTAssertTrue(app.staticTexts["QUADRA GLASS"].exists)
        app.buttons["reset-controls"].tap()
        XCTAssertTrue(app.buttons["pattern-quadra"].isSelected)
    }

    @MainActor func testVideo01RecordingAndPlayback() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the attached camera and microphone")
        #else
        let app=XCUIApplication()
        let monitor=addUIInterruptionMonitor(withDescription: "Recording permissions") { alert in
            for title in ["Allow","OK","허용","확인","Allow Adding Photos","사진 추가 허용"] {
                if alert.buttons[title].exists { alert.buttons[title].tap(); return true }
            }
            return false
        }
        app.launch()
        XCTAssertTrue(app.buttons["mode-video"].waitForExistence(timeout: 15))
        app.buttons["mode-video"].tap()
        expectation(for: NSPredicate(format: "enabled == true"),evaluatedWith: app.buttons["shutter"])
        waitForExpectations(timeout: 20)
        app.buttons["shutter"].tap()
        sleep(1); app.tap()
        expectation(for: NSPredicate(format: "label == '녹화 종료'"),evaluatedWith: app.buttons["shutter"])
        waitForExpectations(timeout: 20)
        XCTAssertFalse(app.buttons["mode-photo"].isEnabled)
        XCTAssertFalse(app.buttons["전후면 카메라 전환"].isEnabled)
        app.buttons["pattern-crossLarge"].tap()
        XCTAssertTrue(app.buttons["pattern-crossLarge"].isSelected)
        sleep(2)
        app.buttons["control-pitch"].tap()
        dragDial(in: app,toRight: false)
        app.buttons["pattern-diamond"].tap()
        XCTAssertTrue(app.buttons["pattern-diamond"].isSelected)
        sleep(2)
        let recording=XCTAttachment(screenshot: app.screenshot())
        recording.name="glass-video-recording"; recording.lifetime = .keepAlways; add(recording)
        app.buttons["shutter"].tap()
        XCTAssertTrue(app.staticTexts["동영상을 사진 앱에 저장했어요"].waitForExistence(timeout: 60))
        app.buttons["recent-capture"].tap()
        XCTAssertTrue(app.navigationBars["최근 촬영"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["공유"].exists)
        assertVideoVisible(in: app)
        let playback=XCTAttachment(screenshot: app.screenshot())
        playback.name="glass-video-playback"; playback.lifetime = .keepAlways; add(playback)
        app.buttons["닫기"].tap()
        app.buttons["recent-capture"].tap()
        assertVideoVisible(in: app)
        app.buttons["닫기"].tap()
        app.buttons["reset-controls"].tap()
        removeUIInterruptionMonitor(monitor)
        #endif
    }

    @MainActor func testVideo02FrontCameraBackgroundFinish() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the attached camera")
        #else
        let app=XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["mode-video"].waitForExistence(timeout: 15))
        app.buttons["mode-video"].tap()
        expectation(for: NSPredicate(format: "enabled == true"),evaluatedWith: app.buttons["shutter"])
        waitForExpectations(timeout: 20)
        app.buttons["전후면 카메라 전환"].tap()
        sleep(2)
        app.buttons["shutter"].tap()
        expectation(for: NSPredicate(format: "label == '녹화 종료'"),evaluatedWith: app.buttons["shutter"])
        waitForExpectations(timeout: 20)
        sleep(3)
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(app.staticTexts["동영상을 사진 앱에 저장했어요"].waitForExistence(timeout: 60))
        XCTAssertEqual(app.buttons["shutter"].label,"녹화 시작")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let result=XCTAttachment(screenshot: app.screenshot())
        result.name="front-video-background-finished"; result.lifetime = .keepAlways; add(result)
        #endif
    }

    @MainActor private func dial(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "glass-dial").firstMatch
    }

    // Run against a lit camera scene. Inspect the image area, excluding player
    // controls and navigation: opening an empty player must not count as playback.
    @MainActor private func assertVideoVisible(in app: XCUIApplication) {
        let visible=NSPredicate { _,_ in
            let screenshot=app.screenshot().image.cgImage!
            let area=CGRect(x: Double(screenshot.width)*0.15,y: Double(screenshot.height)*0.35,
                            width: Double(screenshot.width)*0.7,height: Double(screenshot.height)*0.25)
            guard let crop=screenshot.cropping(to: area) else { return false }
            var pixels=[UInt8](repeating: 0,count: 32*32*4)
            return pixels.withUnsafeMutableBytes { bytes in
                let context=CGContext(data: bytes.baseAddress,width: 32,height: 32,bitsPerComponent: 8,
                    bytesPerRow: 128,space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(crop,in: CGRect(x: 0,y: 0,width: 32,height: 32))
                let values=bytes.bindMemory(to: UInt8.self)
                let lit=(0..<1024).filter { max(values[$0*4],values[$0*4+1],values[$0*4+2])>20 }.count
                return lit>102
            }
        }
        let result=XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible,object: nil)],timeout: 10)
        XCTAssertEqual(result,.completed,"The playback image area is black")
    }

    @MainActor private func dragDial(in app: XCUIApplication, toRight: Bool) {
        let control=dial(in: app)
        let start=control.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.18))
        let end=control.coordinate(withNormalizedOffset: CGVector(dx: toRight ? 0.86 : 0.14,dy: 0.87))
        start.press(forDuration: 0.1,thenDragTo: end)
    }

    @MainActor func testSampleToFrontCamera() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires front and rear cameras on an iPhone")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["--sample"]
        app.launch()
        XCTAssertTrue(app.buttons["카메라로 돌아가기"].waitForExistence(timeout: 15))
        app.buttons["카메라로 돌아가기"].tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["shutter"])
        waitForExpectations(timeout: 20)
        app.buttons["전후면 카메라 전환"].tap()
        // Allow the new camera's first buffers to replace the previous frame.
        sleep(2)
        XCTAssertTrue(app.staticTexts["LIVE"].exists)
        XCTAssertTrue(app.buttons["shutter"].isEnabled)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "front-camera-preview"
        attachment.lifetime = .keepAlways
        add(attachment)
        #endif
    }

    @MainActor func testLiveCameraAndFullResolutionCapture() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the attached physical iPhone")
        #else
        let app=XCUIApplication()
        app.launchArguments=["--device-validation"]
        let monitor=addUIInterruptionMonitor(withDescription: "Camera permission") { alert in
            for title in ["Allow","OK","허용","확인"] {
                if alert.buttons[title].exists { alert.buttons[title].tap(); return true }
            }
            return false
        }
        app.launch()
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 20))
        app.tap()
        let ready=NSPredicate(format:"enabled == true")
        expectation(for: ready,evaluatedWith: app.buttons["shutter"])
        waitForExpectations(timeout: 20)
        XCTAssertTrue(app.staticTexts["LIVE"].exists)
        let preview=XCTAttachment(screenshot: app.screenshot())
        preview.name="physical-iphone-live"; preview.lifetime = .keepAlways; add(preview)
        app.buttons["shutter"].tap()
        app.buttons["control-relief"].tap()
        XCTAssertTrue(dial(in: app).waitForExistence(timeout: 5))
        dragDial(in: app,toRight: false)
        XCTAssertTrue(app.staticTexts["검증 사진 저장 완료"].waitForExistence(timeout: 45))
        app.buttons["reset-controls"].tap()
        let result=XCTAttachment(screenshot: app.screenshot())
        result.name="physical-iphone-after-capture"; result.lifetime = .keepAlways; add(result)
        removeUIInterruptionMonitor(monitor)
        #endif
    }

    @MainActor func testSampleControlsAndCapture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--sample"]
        app.launch()
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 15))
        let control=dial(in: app)
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        let preview=app.descendants(matching: .any).matching(identifier: "camera-preview").firstMatch
        XCTAssertTrue(preview.exists)
        XCTAssertGreaterThanOrEqual(control.frame.minY,preview.frame.maxY)
        let initialPreviewFrame=preview.frame
        app.buttons["reset-controls"].tap()
        for key in ["thickness","relief","pitch","roundness"] {
            let tab=app.buttons["control-\(key)"]
            XCTAssertTrue(tab.isHittable,"Main control is hidden: \(key)")
            XCTAssertGreaterThanOrEqual(tab.frame.minY,preview.frame.maxY)
            tab.tap()
            let before=control.value as? String
            dragDial(in: app,toRight: true)
            XCTAssertNotEqual(control.value as? String,before,"Dial did not update \(key)")
            XCTAssertFalse(app.alerts.firstMatch.exists)
            XCTAssertEqual(preview.frame,initialPreviewFrame,"Choosing a control moved the preview")
        }
        // Coupled thickness/relief endpoint stays valid without an error popup.
        app.buttons["control-thickness"].tap()
        dragDial(in: app,toRight: false)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.buttons["reset-controls"].tap()
        app.buttons["control-relief"].tap()
        let controls=XCTAttachment(screenshot: app.screenshot())
        controls.name="unobstructed-protractor-controls"; controls.lifetime = .keepAlways; add(controls)
        app.buttons["compare"].tap()
        XCTAssertTrue(app.staticTexts["ORIGINAL"].exists)
        app.buttons["compare"].tap()
        XCTAssertTrue(app.staticTexts["QUADRA GLASS"].exists)
        let monitor = addUIInterruptionMonitor(withDescription: "Photos permission") { alert in
            for title in ["Allow Adding Photos", "Allow Access to Add Photos", "Allow", "사진 추가 허용", "허용"] {
                if alert.buttons[title].exists { alert.buttons[title].tap(); return true }
            }
            return false
        }
        app.buttons["shutter"].tap()
        sleep(3)
        app.tap()
        XCTAssertTrue(app.staticTexts["사진 앱에 저장했어요"].waitForExistence(timeout: 30))
        removeUIInterruptionMonitor(monitor)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "quadra-sample-camera"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // App Store marketing captures. Sample mode keeps the simulator free of camera
    // hardware and permission dialogs; each stop is attached as store-N-<name>.
    @MainActor func testAppStoreScreenshots() throws {
        let app=XCUIApplication()
        app.launchArguments=["--sample"]
        app.launch()
        XCTAssertTrue(app.buttons["reset-controls"].waitForExistence(timeout: 30))
        app.buttons["reset-controls"].tap()
        sleep(2)
        shoot(app,"store-1-quadra")

        app.buttons["pattern-diamond"].tap()
        sleep(2)
        shoot(app,"store-2-diamond")

        app.buttons["pattern-crossLarge"].tap()
        sleep(2)
        shoot(app,"store-3-cross")

        app.buttons["pattern-quadra"].tap()
        app.buttons["control-relief"].tap()
        dragDial(in: app,toRight: true)
        sleep(2)
        shoot(app,"store-4-dial")

        app.buttons["compare"].tap()
        XCTAssertTrue(app.staticTexts["ORIGINAL"].waitForExistence(timeout: 10))
        sleep(1)
        shoot(app,"store-5-original")
        app.buttons["compare"].tap()

        app.buttons["mode-video"].tap()
        sleep(2)
        shoot(app,"store-6-video")
    }

    @MainActor private func shoot(_ app: XCUIApplication,_ name: String) {
        let shot=XCTAttachment(screenshot: app.screenshot())
        shot.name=name; shot.lifetime = .keepAlways; add(shot)
    }
}
