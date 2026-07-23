import Carbon.HIToolbox
import XCTest
@testable import Drawer

final class HotkeyBindingTests: XCTestCase {
    func testSingleKeyLabel() {
        let binding = HotkeyBinding(keyCode: UInt32(kVK_F13), modifiers: 0)
        XCTAssertEqual(binding.label, "F13")
        XCTAssertTrue(binding.isSingleKey)
        XCTAssertFalse(binding.isTypingKey)
    }

    func testModifierLabel() {
        XCTAssertEqual(HotkeyBinding.ctrlOptSpace.label, "⌃⌥Space")
    }

    func testTappedModifierIsOneCap() {
        let binding = HotkeyBinding.tap(UInt32(kVK_RightCommand))
        XCTAssertEqual(binding.parts, ["right ⌘"])
        XCTAssertTrue(binding.isModifierTap)
        XCTAssertEqual(binding.tapFlag, .command)
        XCTAssertTrue(binding.needsAccessibility)
        XCTAssertNil(binding.problem)
    }

    func testTappedModifierSurvivesASaveAndLoad() {
        let defaults = UserDefaults.standard
        let priorCode = defaults.object(forKey: "hotkeyKeyCode")
        let priorMods = defaults.object(forKey: "hotkeyModifiers")

        let binding = HotkeyBinding.tap(UInt32(kVK_Option))
        binding.save()
        XCTAssertEqual(HotkeyBinding.saved, binding)
        XCTAssertTrue(HotkeyBinding.saved.isModifierTap)

        if let priorCode {
            defaults.set(priorCode, forKey: "hotkeyKeyCode")
        } else {
            defaults.removeObject(forKey: "hotkeyKeyCode")
        }
        if let priorMods {
            defaults.set(priorMods, forKey: "hotkeyModifiers")
        } else {
            defaults.removeObject(forKey: "hotkeyModifiers")
        }
    }

    func testAKeyIsNotATappableModifier() {
        XCTAssertNil(HotkeyBinding.tap(UInt32(kVK_ANSI_A)).tapFlag)
        XCTAssertNotNil(HotkeyBinding.tap(UInt32(kVK_ANSI_A)).problem)
    }

    func testLetterKeyIsTypingKey() {
        let binding = HotkeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: 0)
        XCTAssertTrue(binding.isTypingKey)
    }

    func testSaveAndLoad() {
        let defaults = UserDefaults.standard
        let priorCode = defaults.object(forKey: "hotkeyKeyCode")
        let priorMods = defaults.object(forKey: "hotkeyModifiers")

        let binding = HotkeyBinding(keyCode: UInt32(kVK_F15), modifiers: 0)
        binding.save()
        XCTAssertEqual(HotkeyBinding.saved, binding)

        if let priorCode {
            defaults.set(priorCode, forKey: "hotkeyKeyCode")
        } else {
            defaults.removeObject(forKey: "hotkeyKeyCode")
        }
        if let priorMods {
            defaults.set(priorMods, forKey: "hotkeyModifiers")
        } else {
            defaults.removeObject(forKey: "hotkeyModifiers")
        }
    }
}
