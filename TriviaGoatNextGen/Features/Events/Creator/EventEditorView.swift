//  EventEditorView.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  Canonical event creation/editing surface.
//  Uses EventDraft as the single source of truth.
//

import SwiftUI

struct EventEditorView: View {

    @EnvironmentObject private var app: AppState

    @State private var draft = EventDraft()
    @State private var didHydrateForEdit = false

    @State private var hasStartDate: Bool = true
    @State private var hasEndDate: Bool = true

    @State private var startDate: Date = Calendar.current.date(
        byAdding: .day,
        value: 7,
        to: Date()
    ) ?? Date()

    @State private var endDate: Date = Calendar.current.date(
        byAdding: .hour,
        value: 2,
        to: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    ) ?? Date()

    @State private var rsvpOpensAt: Date = Date()

    @State private var rsvpClosesAt: Date = Calendar.current.date(
        byAdding: .day,
        value: 6,
        to: Date()
    ) ?? Date()

    @State private var waitlistOpensAt: Date = Date()

    @State private var waitlistClosesAt: Date = Calendar.current.date(
        byAdding: .day,
        value: 6,
        to: Date()
    ) ?? Date()

    private var editingEvent: AppState.TGEvent? {
        app.selectedEvent
    }

    private var isEditMode: Bool {
        editingEvent != nil
    }

    private var trimmedTitle: String {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedHeroLine: String {
        draft.heroLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSummary: String {
        draft.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasTitle: Bool { !trimmedTitle.isEmpty }
    private var hasHeroLine: Bool { !trimmedHeroLine.isEmpty }
    private var hasSummary: Bool { !trimmedSummary.isEmpty }

    private var scheduleIsValid: Bool {
        hasStartDate && hasEndDate && startDate < endDate
    }

    private var rsvpWindowIsValid: Bool {
        rsvpOpensAt <= rsvpClosesAt && rsvpClosesAt <= startDate
    }

    private var waitlistWindowIsValid: Bool {
        waitlistOpensAt <= waitlistClosesAt && waitlistClosesAt <= startDate
    }

    private var capacityIsValid: Bool {
        draft.capacity > 0
    }

    private var completionScore: Int {
        [
            hasTitle,
            hasSummary,
            scheduleIsValid,
            rsvpWindowIsValid,
            waitlistWindowIsValid,
            capacityIsValid
        ].filter { $0 }.count
    }

    private var completionTotal: Int { 6 }

    private var completionProgress: CGFloat {
        CGFloat(completionScore) / CGFloat(completionTotal)
    }

    private var canSaveDraft: Bool {
        completionScore == completionTotal
    }

    private var readinessText: String {
        if !hasTitle { return "Add an event title" }
        if !hasSummary { return "Add an event summary" }
        if !hasStartDate { return "Start date required" }
        if !hasEndDate { return "End date required" }
        if startDate >= endDate { return "End date must be after start date" }
        if rsvpOpensAt > rsvpClosesAt { return "RSVP open must be before RSVP close" }
        if rsvpClosesAt > startDate { return "RSVP must close before event starts" }
        if waitlistOpensAt > waitlistClosesAt { return "Waitlist open must be before waitlist close" }
        if waitlistClosesAt > startDate { return "Waitlist must close before event starts" }
        if draft.capacity <= 0 { return "Capacity required" }
        return isEditMode ? "Ready to update draft" : "Ready to save draft"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpaceBackground()

                VStack(spacing: 0) {
                    header(safeTop: geo.safeAreaInsets.top)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            commandPanel
                            readinessPanel

                            fieldCard(
                                "TITLE",
                                text: $draft.title,
                                placeholder: "Event title",
                                isComplete: hasTitle,
                                isRequired: true
                            )

                            fieldCard(
                                "HERO LINE",
                                text: $draft.heroLine,
                                placeholder: "Short event subtitle",
                                isComplete: hasHeroLine,
                                isRequired: false
                            )

                            fieldCard(
                                "SUMMARY",
                                text: $draft.summary,
                                placeholder: "Full event description",
                                isComplete: hasSummary,
                                isRequired: true,
                                axis: .vertical
                            )

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
                hydrateForEditIfNeeded()
                normalizeDateState()
                syncDraftDates()
            }
            .onChange(of: startDate) { _, _ in normalizeDateState(); syncDraftDates() }
            .onChange(of: endDate) { _, _ in normalizeDateState(); syncDraftDates() }
            .onChange(of: rsvpOpensAt) { _, _ in normalizeDateState(); syncDraftDates() }
            .onChange(of: rsvpClosesAt) { _, _ in normalizeDateState(); syncDraftDates() }
            .onChange(of: waitlistOpensAt) { _, _ in normalizeDateState(); syncDraftDates() }
            .onChange(of: waitlistClosesAt) { _, _ in normalizeDateState(); syncDraftDates() }
            .onChange(of: draft.capacity) { _, _ in syncDraftDates() }
        }
    }

    private func header(safeTop: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.instance.impact(.light)
                SpatialAudioManager.shared.play(.uiTap)
                app.setRoute(isEditMode ? .manageEvent : .creatorConsole)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.09)))
                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(isEditMode ? "EDIT EVENT" : "CREATE EVENT")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.96))
                    .tracking(1.8)

                Text(isEditMode ? "Update draft details" : "Draft → Review → Public")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.50))
            }

            Spacer()

            completionBadge
        }
        .padding(.horizontal, 16)
        .padding(.top, safeTop + 8)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.76).ignoresSafeArea(edges: .top))
    }

    private var completionBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: canSaveDraft ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 12, weight: .black))

            Text("\(completionScore)/\(completionTotal)")
                .font(.system(size: 10, weight: .black, design: .monospaced))
        }
        .foregroundColor(canSaveDraft ? .black.opacity(0.88) : .orange.opacity(0.95))
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(
            Capsule()
                .fill(canSaveDraft ? Color.green.opacity(0.95) : Color.orange.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(canSaveDraft ? Color.green.opacity(0.30) : Color.orange.opacity(0.26), lineWidth: 1)
        )
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isEditMode ? "EVENT EDIT" : "EVENT DRAFT")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.94))
                    .tracking(2.2)

                Spacer()

                statusCapsule(canSaveDraft ? "READY" : "IN PROGRESS", isComplete: canSaveDraft)
            }

            Text(isEditMode
                 ? "Refine this event without creating a duplicate record."
                 : "Build a launch-ready event with clear timing, RSVP windows, waitlist controls, and creator operations.")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.88))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(readinessText.uppercased())
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(canSaveDraft ? .green.opacity(0.92) : .orange.opacity(0.88))
                .tracking(1.2)
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.82))

                LinearGradient(
                    colors: [
                        Color.orange.opacity(0.18),
                        Color.blue.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(canSaveDraft ? Color.green.opacity(0.36) : Color.orange.opacity(0.24), lineWidth: 1.2)
        )
        .shadow(color: Color.orange.opacity(0.12), radius: 22, x: 0, y: 12)
    }

    private var readinessPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("BUILD READINESS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(2)

                Spacer()

                Text("\(Int(completionProgress * 100))%")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(canSaveDraft ? .green.opacity(0.94) : .white.opacity(0.58))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))

                    Capsule()
                        .fill(canSaveDraft ? Color.green.opacity(0.95) : Color.orange.opacity(0.92))
                        .frame(width: max(8, proxy.size.width * completionProgress))
                }
            }
            .frame(height: 10)

            HStack(spacing: 8) {
                miniStatus("TITLE", hasTitle)
                miniStatus("SUMMARY", hasSummary)
                miniStatus("TIME", scheduleIsValid)
            }

            HStack(spacing: 8) {
                miniStatus("RSVP", rsvpWindowIsValid)
                miniStatus("WAITLIST", waitlistWindowIsValid)
                miniStatus("CAPACITY", capacityIsValid)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.052)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func miniStatus(_ title: String, _ isComplete: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .black))

            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(0.5)
        }
        .foregroundColor(isComplete ? .green.opacity(0.94) : .white.opacity(0.36))
        .padding(.horizontal, 8)
        .frame(height: 25)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(isComplete ? Color.green.opacity(0.10) : Color.white.opacity(0.045)))
        .overlay(Capsule().stroke(isComplete ? Color.green.opacity(0.20) : Color.white.opacity(0.07), lineWidth: 1))
    }

    private func fieldCard(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        isComplete: Bool,
        isRequired: Bool,
        axis: Axis = .horizontal
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(isComplete ? .green.opacity(0.94) : .orange.opacity(0.92))
                    .tracking(2)

                Spacer()

                statusCapsule(isComplete ? "SET" : (isRequired ? "REQUIRED" : "OPTIONAL"), isComplete: isComplete)
            }

            TextField(placeholder, text: text, axis: axis)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(isComplete ? .white : .white.opacity(0.70))
                .tint(.orange)
                .lineLimit(axis == .vertical ? 4...8 : 1...1)
        }
        .padding(17)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isComplete ? Color.green.opacity(0.075) : Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isComplete ? Color.green.opacity(0.30) : Color.white.opacity(0.10), lineWidth: 1.2)
        )
    }

    private var schedulePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader(
                title: "TIMELINE CONTROL",
                subtitle: "Tap any date card to adjust schedule, RSVP, or waitlist timing"
            )

            premiumDateRow(
                title: "EVENT START",
                subtitle: "Public start time",
                selection: $startDate,
                isComplete: scheduleIsValid,
                icon: "flag.checkered"
            )

            premiumDateRow(
                title: "EVENT END",
                subtitle: "Must be after start",
                selection: $endDate,
                range: startDate.addingTimeInterval(60 * 30)...,
                isComplete: scheduleIsValid,
                icon: "flag.fill"
            )

            timelineDivider

            premiumDateRow(
                title: "RSVP OPENS",
                subtitle: "Player registration opens",
                selection: $rsvpOpensAt,
                isComplete: rsvpWindowIsValid,
                icon: "person.crop.circle.badge.plus"
            )

            premiumDateRow(
                title: "RSVP CLOSES",
                subtitle: "Must close before event starts",
                selection: $rsvpClosesAt,
                range: rsvpOpensAt...startDate,
                isComplete: rsvpWindowIsValid,
                icon: "person.crop.circle.badge.checkmark"
            )

            timelineDivider

            premiumDateRow(
                title: "WAITLIST OPENS",
                subtitle: "Overflow queue opens",
                selection: $waitlistOpensAt,
                isComplete: waitlistWindowIsValid,
                icon: "person.3.sequence.fill"
            )

            premiumDateRow(
                title: "WAITLIST CLOSES",
                subtitle: "Must close before event starts",
                selection: $waitlistClosesAt,
                range: waitlistOpensAt...startDate,
                isComplete: waitlistWindowIsValid,
                icon: "person.3.fill"
            )

            schedulePreview
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.055))

                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.10),
                        Color.orange.opacity(0.06),
                        Color.clear
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    scheduleIsValid && rsvpWindowIsValid && waitlistWindowIsValid
                    ? Color.green.opacity(0.24)
                    : Color.white.opacity(0.10),
                    lineWidth: 1.2
                )
        )
    }

    private var timelineDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
            .padding(.vertical, 2)
    }

    private func premiumDateRow(
        title: String,
        subtitle: String,
        selection: Binding<Date>,
        isComplete: Bool,
        icon: String
    ) -> some View {
        premiumDateCard(
            title: title,
            subtitle: subtitle,
            selection: selection,
            isComplete: isComplete,
            icon: icon
        )
    }

    private func premiumDateRow(
        title: String,
        subtitle: String,
        selection: Binding<Date>,
        range: PartialRangeFrom<Date>,
        isComplete: Bool,
        icon: String
    ) -> some View {
        premiumDateCard(
            title: title,
            subtitle: subtitle,
            selection: selection,
            range: range,
            isComplete: isComplete,
            icon: icon
        )
    }

    private func premiumDateRow(
        title: String,
        subtitle: String,
        selection: Binding<Date>,
        range: ClosedRange<Date>,
        isComplete: Bool,
        icon: String
    ) -> some View {
        premiumDateCard(
            title: title,
            subtitle: subtitle,
            selection: selection,
            closedRange: range,
            isComplete: isComplete,
            icon: icon
        )
    }

    private func premiumDateCard(
        title: String,
        subtitle: String,
        selection: Binding<Date>,
        isComplete: Bool,
        icon: String
    ) -> some View {
        premiumDateCardBody(
            title: title,
            subtitle: subtitle,
            isComplete: isComplete,
            icon: icon,
            picker: AnyView(
                DatePicker("", selection: selection, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(.orange)
            )
        )
    }

    private func premiumDateCard(
        title: String,
        subtitle: String,
        selection: Binding<Date>,
        range: PartialRangeFrom<Date>,
        isComplete: Bool,
        icon: String
    ) -> some View {
        premiumDateCardBody(
            title: title,
            subtitle: subtitle,
            isComplete: isComplete,
            icon: icon,
            picker: AnyView(
                DatePicker(
                    "",
                    selection: selection,
                    in: range,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(.orange)
            )
        )
    }

    private func premiumDateCard(
        title: String,
        subtitle: String,
        selection: Binding<Date>,
        closedRange: ClosedRange<Date>,
        isComplete: Bool,
        icon: String
    ) -> some View {
        premiumDateCardBody(
            title: title,
            subtitle: subtitle,
            isComplete: isComplete,
            icon: icon,
            picker: AnyView(
                DatePicker(
                    "",
                    selection: selection,
                    in: closedRange,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(.orange)
            )
        )
    }

    private func premiumDateCardBody(
        title: String,
        subtitle: String,
        isComplete: Bool,
        icon: String,
        picker: AnyView
    ) -> some View {
        let titleColor = isComplete ? Color.green.opacity(0.94) : Color.white.opacity(0.78)
        let iconColor = isComplete ? Color.green.opacity(0.95) : Color.white.opacity(0.28)
        let statusText = isComplete ? "SELECTED" : "NEEDS REVIEW"
        let statusColor = isComplete ? Color.green.opacity(0.88) : Color.orange.opacity(0.82)
        let fillColor = isComplete ? Color.green.opacity(0.07) : Color.black.opacity(0.25)
        let strokeColor = isComplete ? Color.green.opacity(0.22) : Color.white.opacity(0.07)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                dateIcon(icon, isComplete)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(titleColor)
                            .tracking(1)

                        Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(iconColor)
                    }

                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.46))
                        .lineLimit(2)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(statusText)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(statusColor)
                    .tracking(1.1)

                picker
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isComplete ? Color.green.opacity(0.18) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
    }

    private func dateIcon(_ icon: String, _ isComplete: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .black))
            .foregroundColor(isComplete ? .green.opacity(0.92) : .orange.opacity(0.88))
            .frame(width: 36, height: 36)
            .background(Circle().fill(isComplete ? Color.green.opacity(0.12) : Color.orange.opacity(0.10)))
            .overlay(Circle().stroke(isComplete ? Color.green.opacity(0.22) : Color.orange.opacity(0.16), lineWidth: 1))
    }

    private var schedulePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PUBLIC DATE PREVIEW")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48))
                    .tracking(1)

                Spacer()

                Image(systemName: scheduleIsValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(scheduleIsValid ? .green.opacity(0.92) : .orange.opacity(0.92))
            }

            Text(formattedSchedulePreview)
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundColor(scheduleIsValid ? .green.opacity(0.94) : .orange.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.36)))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(scheduleIsValid ? Color.green.opacity(0.22) : Color.orange.opacity(0.12), lineWidth: 1)
        )
    }

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader(title: "EVENT SETTINGS", subtitle: "Capacity, waitlist, and operational defaults")

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WAITLIST ENABLED")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(draft.waitlistEnabled ? .green.opacity(0.94) : .white.opacity(0.52))
                        .tracking(1.3)

                    Text(draft.waitlistEnabled ? "Overflow players can join the queue" : "Waitlist is currently off")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.44))
                }

                Spacer()

                Toggle("", isOn: $draft.waitlistEnabled)
                    .labelsHidden()
                    .tint(.orange)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CAPACITY")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(capacityIsValid ? .green.opacity(0.94) : .orange.opacity(0.92))
                        .tracking(1.3)

                    Text(draft.capacity == 0 ? "Open capacity" : "\(draft.capacity) seats available")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.88))
                }

                Spacer()

                Stepper("", value: $draft.capacity, in: 0...10000, step: 25)
                    .labelsHidden()
            }

            Text(capacityIsValid ? "Capacity is set and ready." : "Set capacity above 0 before saving this event.")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(capacityIsValid ? .green.opacity(0.64) : .orange.opacity(0.72))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(capacityIsValid ? Color.green.opacity(0.055) : Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(capacityIsValid ? Color.green.opacity(0.22) : Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var ecosystemPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader(title: "EVENT ECOSYSTEM", subtitle: "Unlocks after draft creation")

            ecosystemRow("SESSION BUILDER", "rectangle.3.group.fill")
            ecosystemRow("DELEGATE ROLES", "person.3.fill")
            ecosystemRow("GUEST PANEL", "person.2.badge.gearshape.fill")
            ecosystemRow("CHECK-IN OPS", "qrcode.viewfinder")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private func panelHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            Text(subtitle)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.52))
        }
    }

    private func ecosystemRow(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
                .foregroundColor(.orange.opacity(0.88))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.orange.opacity(0.12)))

            Text(title)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.80))
                .tracking(0.8)

            Spacer()

            Text("NEXT")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.42))
                .tracking(1)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.32)))
    }

    private var saveButton: some View {
        Button {
            HapticManager.instance.impact(.medium)
            SpatialAudioManager.shared.play(.uiTap)

            guard canSaveDraft else {
                app.showEventToast(readinessText.uppercased())
                return
            }

            finalizeDraftText()
            syncDraftDates()

            if let editingEvent {
                app.updateEventDraft(eventID: editingEvent.id, draft: draft)
            } else {
                app.saveEventDraft(draft)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: canSaveDraft ? "checkmark.circle.fill" : "lock.fill")
                    .font(.system(size: 15, weight: .black))

                Text(canSaveDraft ? (isEditMode ? "UPDATE DRAFT" : "SAVE DRAFT") : "COMPLETE REQUIRED DETAILS")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .tracking(1.1)

                Spacer()

                Text("\(completionScore)/\(completionTotal)")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(0.8)
            }
            .foregroundColor(canSaveDraft ? .black.opacity(0.90) : .white.opacity(0.58))
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(canSaveDraft ? Color.orange.opacity(0.96) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(canSaveDraft ? Color.orange.opacity(0.32) : Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: canSaveDraft ? Color.orange.opacity(0.22) : Color.clear, radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func statusCapsule(_ title: String, isComplete: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 9, weight: .black))

            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(0.7)
        }
        .foregroundColor(isComplete ? .black.opacity(0.86) : .white.opacity(0.58))
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(isComplete ? Color.green.opacity(0.92) : Color.white.opacity(0.08)))
        .overlay(Capsule().stroke(isComplete ? Color.green.opacity(0.25) : Color.white.opacity(0.10), lineWidth: 1))
    }

    private var formattedSchedulePreview: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d • h:mm a"

        let start = formatter.string(from: startDate).uppercased()
        let safeEnd = max(endDate, startDate.addingTimeInterval(60 * 30))
        let end = formatter.string(from: safeEnd).uppercased()

        return "\(start) → \(end)"
    }
    
    private func formattedPickerDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func formattedPickerTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func hydrateForEditIfNeeded() {
        guard !didHydrateForEdit else { return }
        didHydrateForEdit = true

        guard let event = editingEvent else {
            normalizeDateState()
            syncDraftDates()
            return
        }

        draft.title = event.title
        draft.heroLine = event.heroLine
        draft.summary = event.summary
        draft.capacity = max(1, event.capacity)
        draft.waitlistEnabled = event.waitlistEnabled

        startDate = event.startsAt ?? startDate
        endDate = event.endsAt ?? startDate.addingTimeInterval(2 * 60 * 60)

        rsvpOpensAt = event.rsvpOpensAt ?? startDate.addingTimeInterval(-7 * 24 * 60 * 60)
        rsvpClosesAt = event.rsvpClosesAt ?? startDate.addingTimeInterval(-60 * 60)

        waitlistOpensAt = event.waitlistOpensAt ?? rsvpOpensAt
        waitlistClosesAt = event.waitlistClosesAt ?? rsvpClosesAt

        normalizeDateState()
        syncDraftDates()
    }

    private func normalizeDateState() {
        let minimumEnd = startDate.addingTimeInterval(60 * 30)

        if endDate < minimumEnd {
            endDate = startDate.addingTimeInterval(2 * 60 * 60)
        }

        let latestClose = startDate.addingTimeInterval(-60 * 60)

        if rsvpClosesAt > latestClose {
            rsvpClosesAt = latestClose
        }

        if rsvpOpensAt > rsvpClosesAt {
            rsvpOpensAt = rsvpClosesAt.addingTimeInterval(-24 * 60 * 60)
        }

        if waitlistClosesAt > latestClose {
            waitlistClosesAt = latestClose
        }

        if waitlistOpensAt > waitlistClosesAt {
            waitlistOpensAt = waitlistClosesAt.addingTimeInterval(-24 * 60 * 60)
        }
    }

    private func finalizeDraftText() {
        draft.title = trimmedTitle
        draft.heroLine = trimmedHeroLine
        draft.summary = trimmedSummary
    }

    private func syncDraftDates() {
        draft.startsAt = startDate
        draft.endsAt = max(endDate, startDate.addingTimeInterval(60 * 30))

        draft.rsvpOpensAt = rsvpOpensAt
        draft.rsvpClosesAt = rsvpClosesAt
        draft.waitlistOpensAt = waitlistOpensAt
        draft.waitlistClosesAt = waitlistClosesAt
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
