import AppKit
@testable import remr

@main
struct NotchCalendarChecks {
    @MainActor
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
            print("PASS: \(message)")
        }
        func advance(_ seconds: TimeInterval) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }
        let context = KeyboardContext(textFieldFocused: false, searchFieldFocused: false,
                                      selectionIsHeader: false, hasSelection: false, searchHasText: false,
                                      selectionIsReminder: false, selectionIsCompleted: false, hasUndo: false)
        func route(_ key: UInt16 = 8, held: Set<UInt16> = [8], context: KeyboardContext = context,
                   bindings: [BindableAction: KeyCombo] = DefaultBindings.all) -> KeyAction {
            KeyboardRouter.action(keyCode: key, heldKeyCodes: held, context: context, bindings: bindings)
        }
        check(route() == .openCalendar, "C opens the calendar without requiring a selection")
        var calendarContext = context
        calendarContext.calendarPresented = true
        check(route(context: calendarContext) == .showMainReminders,
              "C in the calendar returns to the main reminders view")
        calendarContext.textFieldFocused = true
        check(route(context: calendarContext) == .none,
              "Typing in the calendar does not switch views")
        calendarContext.textFieldFocused = false
        check(route(held: [55, 8], context: calendarContext) == .none,
              "Command-C in the calendar remains Copy")
        var editing = context
        editing.textFieldFocused = true
        check(route(context: editing) == .none, "C remains text in the reminder composer")
        var searching = context
        searching.searchFieldFocused = true
        check(route(context: searching) == .none, "C remains text in search")
        check(route(held: [55, 8]) == .none, "Command-C remains Copy")
        check(route(held: [56, 8]) == .none, "Shift-C does not trigger the bare shortcut")
        check(route(held: [8, 14]) == .none, "An incomplete or overlapping chord does not open the calendar")
        var bindings = DefaultBindings.all
        bindings[.openCalendarInApp] = KeyCombo([])
        check(route(bindings: bindings) == .none, "The local calendar shortcut can be disabled")
        bindings[.openCalendarInApp] = KeyCombo([.key(7)])
        check(route(7, held: [7], bindings: bindings) == .openCalendar && route(bindings: bindings) == .none,
              "A custom local calendar binding replaces C")
        check(route(7, held: [7], context: calendarContext, bindings: bindings) == .showMainReminders,
              "A custom calendar shortcut also returns to reminders")
        check(!BindableAction.openCalendarInApp.isGlobalHotkey && BindableAction.openCalendar.isGlobalHotkey,
              "The local shortcut leaves the global calendar shortcut separate")

        let reveal = NotchRevealController()
        reveal.open(animated: true)
        check(!reveal.contentRevealed, "Calendar content and Today glass remain hidden at animation start")
        advance(0.14)
        check(!reveal.contentRevealed, "Content remains hidden halfway through expansion")
        advance(0.17)
        check(reveal.contentRevealed, "Content becomes visible only after the 280 ms expansion")
        reveal.reset()
        reveal.open(animated: true)
        advance(0.04)
        reveal.reset()
        advance(0.3)
        check(!reveal.contentRevealed, "Reset cancels a pending content reveal")
        reveal.open(animated: true)
        advance(0.04)
        reveal.retract()
        advance(0.3)
        check(!reveal.contentRevealed, "Closing cancels a pending content reveal")
        reveal.reset()
        reveal.open(animated: true)
        advance(0.14)
        reveal.reset()
        reveal.open(animated: true)
        advance(0.17)
        check(!reveal.contentRevealed, "A rapid reopen cannot inherit an earlier presentation's reveal")
        advance(0.14)
        check(reveal.contentRevealed, "The reopened panel waits for its own expansion to finish")
        reveal.reset()
        reveal.open(animated: false)
        check(reveal.contentRevealed && reveal.widthRevealed && reveal.heightRevealed,
              "Reduce Motion shows the complete panel immediately")

        let calendarReveal = NotchRevealController(duration: 0.22, contentFadeDuration: 0.08)
        check(calendarReveal.duration < reveal.duration && calendarReveal.contentFadeDuration < reveal.contentFadeDuration,
              "Calendar expansion and content fade are quicker than the main panel")
        calendarReveal.open(animated: true)
        check(!calendarReveal.contentRevealed, "The faster calendar still starts with its contents hidden")
        advance(0.10)
        check(!calendarReveal.contentRevealed, "The faster calendar keeps Today hidden during expansion")
        advance(0.14)
        check(calendarReveal.contentRevealed, "Calendar contents appear after the 220 ms expansion")
        calendarReveal.reset()
        calendarReveal.open(animated: true)
        advance(0.04)
        calendarReveal.reset()
        advance(0.22)
        check(!calendarReveal.contentRevealed, "Closing the faster calendar cancels its pending content reveal")

        let morph = NotchRevealController(duration: 0.22, contentFadeDuration: 0.08)
        check(morph.startWidth(windowWidth: 900, collapsed: 172) == 172
              && morph.startHeight(windowHeight: 1000, collapsed: 33) == 33,
              "Without a morph the calendar starts from the collapsed notch strip")
        morph.startSize = CGSize(width: 560, height: 620)
        check(morph.startWidth(windowWidth: 900, collapsed: 172) == 560
              && morph.startHeight(windowHeight: 1000, collapsed: 33) == 620,
              "The calendar can unfold from the reminders panel's silhouette")
        check(morph.startWidth(windowWidth: 500, collapsed: 172) == 500
              && morph.startHeight(windowHeight: 500, collapsed: 33) == 500,
              "A morph silhouette is clamped to the calendar window")
        morph.retract()
        check(morph.startWidth(windowWidth: 900, collapsed: 172) == 172
              && morph.startHeight(windowHeight: 1000, collapsed: 33) == 33,
              "Retracting returns the calendar's shape to the notch strip")
        morph.startSize = CGSize(width: 560, height: 620)
        morph.reset()
        check(morph.startWidth(windowWidth: 900, collapsed: 172) == 172,
              "Resetting also returns the calendar's shape to the notch strip")

        let reverse = NotchRevealController(duration: 0.22, contentFadeDuration: 0.08)
        reverse.open(animated: false)
        reverse.retract(into: CGSize(width: 580, height: 677))
        check(reverse.startWidth(windowWidth: 1084, collapsed: 172) == 580
              && reverse.startHeight(windowHeight: 965, collapsed: 33) == 677,
              "Returning to reminders shrinks the calendar into the panel's silhouette")
        advance(0.22)
        check(!reverse.contentRevealed && !reverse.widthRevealed && !reverse.heightRevealed,
              "The return settles on the panel silhouette instead of the strip")
        reverse.reset()
        check(reverse.startWidth(windowWidth: 1084, collapsed: 172) == 172,
              "Resetting after the return drops the panel silhouette")
        print("\(checks) notch/calendar checks passed")
    }
}
