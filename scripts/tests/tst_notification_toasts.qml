import QtQuick
import QtTest
import "../../.config/quickshell/components"

TestCase {
    id: test
    name: "NotificationToasts"
    when: windowShown
    width: 800
    height: 500
    property var dismissed: []

    ListModel { id: model }
    NotificationToasts {
        id: first
        width: 400; height: 500
        toastModel: model
        dismissFunc: function(id) { test.dismissed = test.dismissed.concat([id]) }
    }
    // Both monitors share the model; removing a toast destroys both delegates.
    NotificationToasts {
        x: 400; width: 400; height: 500
        toastModel: model
        dismissFunc: first.dismissFunc
    }

    function test_timer_finishes_after_delegate_removal() {
        failOnWarning(/ReferenceError|TypeError/)
        model.append({notifId: 42, appName: "Test", summary: "Toast", body: "",
                      urgency: 0, toastTimeout: 50})
        tryCompare(model, "count", 0, 3000)
        compare(dismissed.length, 1)
        compare(dismissed[0], 42)
        compare(first.hasToasts, false)
    }
}
