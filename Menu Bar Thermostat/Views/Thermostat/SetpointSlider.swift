import SwiftUI

struct SetpointSlider: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    @Binding var coolValue: Double
    var heatValue: Binding<Double>?
    var range: ClosedRange<Double>
    var thumbSize: CGFloat = 24
    var isEnabled: Bool
    var mode: String
    var hvacStatus: String?
    var onDragEnded: ((DraggedSetpointThumb) -> Void)?

    @State private var lastDraggedSetpointThumb: DraggedSetpointThumb = .none

    enum DraggedSetpointThumb {
        case none, cool, heat
    }

    var body: some View {
        GeometryReader { geometry in
            sliderBody(width: geometry.size.width)
        }
        .frame(height: thumbSize)
    }

    private func sliderBody(width: CGFloat) -> some View {
        let trackWidth = width - thumbSize
        let progressCool = CGFloat(clamp((coolValue - range.lowerBound) / (range.upperBound - range.lowerBound), to: 0...1))
        let thumbOffsetCool = progressCool * trackWidth
        let progressHeat = heatValue.map { CGFloat(clamp(($0.wrappedValue - range.lowerBound) / (range.upperBound - range.lowerBound), to: 0...1)) } ?? 0
        let thumbOffsetHeat = progressHeat * trackWidth

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: thumbSize / 2)
                .fill(backgroundTrackColor)
                .frame(height: thumbSize)

            if isEnabled {
                heatTrack(thumbOffsetHeat: thumbOffsetHeat)
                coolTrack(thumbOffsetCool: thumbOffsetCool, trackWidth: trackWidth)
            }

            RoundedRectangle(cornerRadius: thumbSize / 2)
                .stroke(borderColor, lineWidth: 0.5)
                .frame(height: thumbSize)

            if isEnabled {
                heatThumb(thumbOffset: thumbOffsetHeat, trackWidth: trackWidth)
                coolThumb(thumbOffset: thumbOffsetCool, trackWidth: trackWidth)
            }
        }
    }

    private func heatTrack(thumbOffsetHeat: CGFloat) -> some View {
        Group {
            if mode == "HEAT" || mode == "HEATCOOL" {
                RoundedRectangle(cornerRadius: (thumbSize - 2) / 2)
                    .fill(Color.red)
                    .frame(width: max(0, thumbOffsetHeat + thumbSize - 1), height: thumbSize - 2)
                    .offset(x: 1)
            }
        }
    }

    private func coolTrack(thumbOffsetCool: CGFloat, trackWidth: CGFloat) -> some View {
        Group {
            if mode == "HEATCOOL" || mode == "COOL" {
                RoundedRectangle(cornerRadius: (thumbSize - 2) / 2)
                    .fill(Color.blue)
                    .frame(width: max(0, trackWidth - thumbOffsetCool + thumbSize - 1), height: thumbSize - 2)
                    .offset(x: thumbOffsetCool)
            }
        }
    }

    private func heatThumb(thumbOffset: CGFloat, trackWidth: CGFloat) -> some View {
        Group {
            if mode == "HEAT" || mode == "HEATCOOL" {
                sliderThumb(
                    binding: heatValue ?? $coolValue,
                    thumbOffset: thumbOffset,
                    trackWidth: trackWidth,
                    activeThumb: .heat
                )
            }
        }
    }

    private func coolThumb(thumbOffset: CGFloat, trackWidth: CGFloat) -> some View {
        Group {
            if mode == "COOL" || mode == "HEATCOOL" {
                sliderThumb(
                    binding: $coolValue,
                    thumbOffset: thumbOffset,
                    trackWidth: trackWidth,
                    activeThumb: .cool
                )
            }
        }
    }

    private func sliderThumb(binding: Binding<Double>, thumbOffset: CGFloat, trackWidth: CGFloat, activeThumb: DraggedSetpointThumb) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: thumbSize, height: thumbSize)
            .shadow(radius: 2)
            .offset(x: thumbOffset)
            .zIndex(lastDraggedSetpointThumb == activeThumb ? 1 : 0)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        lastDraggedSetpointThumb = activeThumb
                        let translation = max(0, min(trackWidth, value.location.x - thumbSize / 2))
                        let percentage = translation / trackWidth
                        var newValue = Double(percentage) * (range.upperBound - range.lowerBound) + range.lowerBound
                        newValue = clamp(newValue, to: range)

                        let adjustedValues = SetpointSliderLogic.adjustedValues(
                            activeThumb: activeThumb == .heat ? .heat : .cool,
                            proposedValue: newValue,
                            coolValue: coolValue,
                            heatValue: heatValue?.wrappedValue,
                            mode: mode,
                            range: range,
                            minSetpointGap: minSetpointGap
                        )

                        coolValue = adjustedValues.coolValue
                        if let heatValue {
                            heatValue.wrappedValue = adjustedValues.heatValue
                        } else if activeThumb == .heat {
                            binding.wrappedValue = adjustedValues.heatValue
                        }
                    }
                    .onEnded { _ in
                        onDragEnded?(lastDraggedSetpointThumb)
                        lastDraggedSetpointThumb = .none
                    }
            )
    }

    private var minSetpointGap: Double {
        appState.temperatureUnit == .celsius ? 1.67 : 3.0
    }

    private var backgroundTrackColor: Color {
        let isHvacRunning = hvacStatus == "HEATING" || hvacStatus == "COOLING"
        if colorScheme == .dark {
            return Color.black.opacity(0.2)
        } else {
            return isHvacRunning ? Color.gray.opacity(0.3) : Color.black.opacity(0.2)
        }
    }

    private var borderColor: Color {
        if let status = hvacStatus, (status == "HEATING" || status == "COOLING") {
            return .white
        } else {
            return Color(colorScheme == .dark ? .gray : .black).opacity(colorScheme == .dark ? 1 : 0.5)
        }
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
