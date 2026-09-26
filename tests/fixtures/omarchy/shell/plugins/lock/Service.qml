// Test fixture: a minimal stand-in for Omarchy's lock plugin. Only the
// fingerprint retry timer matters to bin/egismoc-fingerprint.
import QtQuick

Item {
  id: root

  function startFingerprint() {}

  Timer {
    id: fingerprintRetryTimer
    interval: 250
    repeat: false
    onTriggered: root.startFingerprint()
  }
}
