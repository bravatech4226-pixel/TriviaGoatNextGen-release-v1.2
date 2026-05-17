//
//  EventEditorView.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-16.
//
//  PURPOSE:
//  Canonical event creation surface.
//  Uses EventDraft as the single source of truth.
//

import SwiftUI

struct EventEditorView: View {

    @EnvironmentObject private var app: AppState

    @State private var draft = EventDraft()

    @State private var hasStartDate: Bool = true
    @State private var startDate: Date = Calendar.current.date(
        byAdding: .day,
        value: 7,
        to: Date()
    ) ?? Date()

    @State private var hasEndDate: Bool = true
    @State private var endDate: Date = Calendar.current.date(
        byAdding: .hour,
        value: 2,
        to: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    ) ?? Date()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpaceBackground()

                VStack(spacing: 0) {
                    header(safeTop: geo.safeAreaInsets.top)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            commandPanel

                            fieldCard("TITLE", text: $draft.title, placeholder: "Event title")
                            fieldCard("HERO LINE", text: $draft.heroLine, placeholder: "Short event subtitle")
                            fieldCard("SUMMARY", text: $draft.summary, placeholder: "Full event description", axis: .vertical)

                            schedulePanel
                            optionsPanel
                            ecosystemPanel
                            saveButton
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 40)
                    }
                }

                toastOverlay
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarHidden(true)
            .onAppear {
                syncDraftDates()
            }
            .onChange(of: hasStartDate) { _, _ in syncDraftDates() }
            .onChange(of: startDate) { _, _ in syncDraftDates() }
            .onChange(of: hasEndDate) { _, _ in syncDraftDates() }
            .onChange(of: endDate) { _, _ in syncDraftDates() }
        }
    }

    private func header(safeTop: CGFloat) -> some View {
        HStack {
            Button {
                HapticManager.instance.impact(.light)
                SpatialAudioManager.shared.play(.uiTap)
                app.setRoute(.creatorConsole)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text("CREATE EVENT")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(1.6)

                Text("Schedule + save draft")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, safeTop + 8)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.72).ignoresSafeArea(edges: .top))
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("EVENT DRAFT")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(2)

                Spacer()

                Text("WDC READY")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.black.opacity(0.86))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.orange.opacity(0.94)))
            }

            Text("Create the event shell first. Sessions, delegates, guest panels, check-in, and messaging can be managed after the event exists.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.orange.opacity(0.20), lineWidth: 1))
    }

    private func fieldCard(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        axis: Axis = .horizontal
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            TextField(placeholder, text: text, axis: axis)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .tint(.orange)
                .lineLimit(axis == .vertical ? 4...8 : 1...1)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var schedulePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader(
                title: "SCHEDULE",
                subtitle: "This controls the public event date and calendar button"
            )

            Toggle("Date Scheduled", isOn: $hasStartDate)
                .tint(.orange)

            if hasStartDate {
                DatePicker(
                    "Starts",
                    selection: $startDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .tint(.orange)

                Toggle("Add End Time", isOn: $hasEndDate)
                    .tint(.orange)

                if hasEndDate {
                    DatePicker(
                        "Ends",
                        selection: $endDate,
                        in: startDate...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .tint(.orange)
                }

                schedulePreview
            } else {
                scheduleTBABox
            }
        }
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .foregroundColor(.white.opacity(0.86))
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var schedulePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PUBLIC DATE PREVIEW")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.42))
                .tracking(1)

            Text(formattedSchedulePreview)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.30)))
    }

    private var scheduleTBABox: some View {
        Text("DATE COMING will show publicly until a start date is added.")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.58))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.30)))
    }

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader(
                title: "EVENT SETTINGS",
                subtitle: "Capacity, waitlist, and operational defaults"
            )

            Toggle("Waitlist Enabled", isOn: $draft.waitlistEnabled)
                .tint(.orange)

            Stepper(
                "Capacity: \(draft.capacity)",
                value: $draft.capacity,
                in: 0...10000,
                step: 25
            )
        }
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .foregroundColor(.white.opacity(0.86))
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var ecosystemPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader(title: "EVENT ECOSYSTEM", subtitle: "Enabled after draft creation")

            ecosystemRow("SESSION BUILDER", "rectangle.3.group.fill")
            ecosystemRow("DELEGATE ROLES", "person.3.fill")
            ecosystemRow("GUEST PANEL", "person.2.badge.gearshape.fill")
            ecosystemRow("CHECK-IN OPS", "qrcode.viewfinder")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private func panelHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            Text(subtitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
        }
    }

    private func ecosystemRow(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
                .foregroundColor(.orange.opacity(0.85))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.orange.opacity(0.10)))

            Text(title)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.76))
                .tracking(0.8)

            Spacer()

            Text("NEXT")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.42))
                .tracking(1)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.30)))
    }

    private var saveButton: some View {
        Button {
            HapticManager.instance.impact(.medium)
            SpatialAudioManager.shared.play(.uiTap)

            syncDraftDates()
            app.saveEventDraft(draft)
        } label: {
            Text("SAVE DRAFT")
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundColor(.black)
                .tracking(1.2)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.orange.opacity(0.96)))
        }
        .buttonStyle(.plain)
    }

    private var formattedSchedulePreview: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d • h:mm a"

        let start = formatter.string(from: startDate).uppercased()

        guard hasEndDate else {
            return start
        }

        let end = formatter.string(from: max(endDate, startDate.addingTimeInterval(60 * 30))).uppercased()
        return "\(start) → \(end)"
    }

    private func syncDraftDates() {
        if hasStartDate {
            draft.startsAt = startDate
        } else {
            draft.startsAt = nil
        }

        if hasStartDate && hasEndDate {
            let minimumEnd = startDate.addingTimeInterval(60 * 30)
            draft.endsAt = endDate < minimumEnd ? minimumEnd : endDate
        } else {
            draft.endsAt = nil
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = app.eventRSVPToastMessage {
            VStack {
                Spacer()

                Text(toast)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Capsule().fill(Color.orange.opacity(0.96)))
                    .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 8)
                    .padding(.bottom, 34)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .allowsHitTesting(false)
            .zIndex(99)
        }
    }
}
