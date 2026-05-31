import Combine
import Foundation

extension ThermostatControlView {
    func startRotationTimer() {
        guard rotationTimer == nil else { return }

        rotationTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                fanAnimationTickCount += 1

                let hvacRunning = currentThermostat.hvacState.isRunning
                let fanTimerOn = currentThermostat.fan.isTimerOn
                let shouldRotate = hvacRunning || fanTimerOn || isManualFanOn

                if shouldRotate {
                    fanRotationAngle -= 1.5
                    if fanRotationAngle <= -360 {
                        fanRotationAngle = 0
                    }
                } else if isRotating {
                    fanRotationAngle = 0
                }

                isRotating = shouldRotate
            }
    }

    func stopRotationTimer() {
        rotationTimer?.cancel()
        rotationTimer = nil
        fanRotationAngle = 0
        fanAnimationTickCount = 0
        isRotating = false
    }
}
