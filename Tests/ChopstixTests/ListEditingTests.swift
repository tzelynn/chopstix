import AppKit
import Testing
@testable import Chopstix

/// Applies back-to-front edits the same way `NoteTextView.apply` does.
private func applying(_ edits: [TextEdit], to string: String) -> String {
    let result = NSMutableString(string: string)
    for edit in edits { result.replaceCharacters(in: edit.range, with: edit.replacement) }
    return result as String
}

private func toggle(_ kind: ListEditing.Kind, _ string: String, _ selection: NSRange) -> String {
    applying(ListEditing.toggleEdits(kind, in: string as NSString, selection: selection), to: string)
}

@Suite struct ListToggleTests {
    @Test func bulletsEverySelectedLine() {
        #expect(toggle(.bullet, "a\nb\nc", NSRange(location: 0, length: 3)) == "• a\n• b\nc")
    }

    @Test func removesBulletsWhenAllAreBulleted() {
        #expect(toggle(.bullet, "• a\n• b", NSRange(location: 0, length: 7)) == "a\nb")
    }

    @Test func mixedSelectionAddsMissingMarkersOnly() {
        #expect(toggle(.bullet, "• a\nb", NSRange(location: 0, length: 5)) == "• a\n• b")
    }

    @Test func convertsBulletsToChecklistAndKeepsTickedItems() {
        #expect(toggle(.checklist, "• a\n☑ b", NSRange(location: 0, length: 7)) == "☐ a\n☑ b")
    }

    @Test func caretOnlyTogglesItsOwnLine() {
        #expect(toggle(.checklist, "a\nb", NSRange(location: 3, length: 0)) == "a\n☐ b")
    }

    @Test func worksOnEmptyTrailingLine() {
        #expect(toggle(.bullet, "a\n", NSRange(location: 2, length: 0)) == "a\n• ")
    }

    @Test func worksOnEmptyText() {
        #expect(toggle(.checklist, "", NSRange(location: 0, length: 0)) == "☐ ")
    }

    @Test func selectionEndingAtLineStartExcludesThatLine() {
        #expect(toggle(.bullet, "a\nb", NSRange(location: 0, length: 2)) == "• a\nb")
    }

    @Test func mapsCaretThroughEdits() {
        let edits = ListEditing.toggleEdits(.bullet, in: "ab\ncd", selection: NSRange(location: 0, length: 5))
        #expect(ListEditing.map(1, through: edits) == 3)  // a|b → • a|b
        #expect(ListEditing.map(4, through: edits) == 8)  // c|d → • c|d
        let removal = ListEditing.toggleEdits(.bullet, in: "• ab", selection: NSRange(location: 1, length: 0))
        #expect(ListEditing.map(1, through: removal) == 0) // caret inside a removed marker snaps to line start
    }
}

@Suite struct ListNewlineTests {
    @Test func plainTextGetsPlainNewline() {
        #expect(ListEditing.newlineEdits(in: "hello", at: 5) == nil)
    }

    @Test func continuesBullets() throws {
        let string = "• milk"
        let result = try #require(ListEditing.newlineEdits(in: string as NSString, at: 6))
        #expect(applying(result.edits, to: string) == "• milk\n• ")
        #expect(result.cursor == 9)
    }

    @Test func continuesChecklistUnticked() throws {
        let string = "☑ done"
        let result = try #require(ListEditing.newlineEdits(in: string as NSString, at: 6))
        #expect(applying(result.edits, to: string) == "☑ done\n☐ ")
    }

    @Test func splitsItemInTheMiddle() throws {
        let string = "• abcd"
        let result = try #require(ListEditing.newlineEdits(in: string as NSString, at: 4))
        #expect(applying(result.edits, to: string) == "• ab\n• cd")
    }

    @Test func emptyItemEndsTheList() throws {
        let string = "• a\n• "
        let result = try #require(ListEditing.newlineEdits(in: string as NSString, at: 6))
        #expect(applying(result.edits, to: string) == "• a\n")
        #expect(result.cursor == 4)
    }

    @Test func caretBeforeMarkerIsPlainNewline() {
        #expect(ListEditing.newlineEdits(in: "• a", at: 0) == nil)
    }
}

@Suite struct CheckboxTests {
    @Test func ticksAndUnticks() throws {
        let edit = try #require(ListEditing.checkboxToggleEdit(in: "x\n☐ buy", at: 2))
        #expect(applying([edit], to: "x\n☐ buy") == "x\n☑ buy")
        let back = try #require(ListEditing.checkboxToggleEdit(in: "☑ buy", at: 0))
        #expect(applying([back], to: "☑ buy") == "☐ buy")
    }

    @Test func ignoresBoxesThatAreNotMarkers() {
        #expect(ListEditing.checkboxToggleEdit(in: "a ☐ b", at: 2) == nil)
        #expect(ListEditing.checkboxToggleEdit(in: "• a", at: 0) == nil)
    }

    @Test func tickedItemsAreStruckThrough() {
        let text = NSMutableAttributedString(string: "☑ done\n☐ todo", attributes: NoteTextStyle.baseAttributes)
        ListEditing.restyleChecklist(in: text)
        let ticked = text.attribute(.strikethroughStyle, at: 3, effectiveRange: nil) as? Int
        let open = text.attribute(.strikethroughStyle, at: 10, effectiveRange: nil) as? Int
        let marker = text.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int
        #expect(ticked == NSUnderlineStyle.single.rawValue)
        #expect(open == nil)
        #expect(marker == nil)
    }
}
