import SwiftUI

struct SettingsPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var showAdvanced = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                
                Text("🪨📄✂️ Battle Simulator")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                
                // MARK: Spawn Mode
                sectionHeader("Spawn Mode")
                
                Picker("", selection: $appState.settings.spawnMode) {
                    ForEach(SpawnMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appState.settings.spawnMode) { _ in
                    appState.restart()
                }
                
                if appState.settings.spawnMode != .click {
                    // Count sliders
                    labeledSlider(
                        label: "🪨 Rock",
                        value: Binding(
                            get: { Double(appState.settings.rockCount) },
                            set: { appState.settings.rockCount = Int($0) }
                        ),
                        range: 0...80, step: 1,
                        display: { "\(Int($0))" }
                    )
                    labeledSlider(
                        label: "📄 Paper",
                        value: Binding(
                            get: { Double(appState.settings.paperCount) },
                            set: { appState.settings.paperCount = Int($0) }
                        ),
                        range: 0...80, step: 1,
                        display: { "\(Int($0))" }
                    )
                    labeledSlider(
                        label: "✂️ Scissors",
                        value: Binding(
                            get: { Double(appState.settings.scissorsCount) },
                            set: { appState.settings.scissorsCount = Int($0) }
                        ),
                        range: 0...80, step: 1,
                        display: { "\(Int($0))" }
                    )
                } else {
                    // Click-to-place panel
                    Text("Pick a type, then click the arena to place icons.")
                        .font(.caption)
                        .opacity(0.7)
                    
                    HStack(spacing: 8) {
                        ForEach(EntityType.allCases, id: \.self) { type in
                            Button(type.emoji) {
                                appState.settings.activeClickType = type
                            }
                            .font(.system(size: 24))
                            .frame(maxWidth: .infinity)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(appState.settings.activeClickType == type ?
                                          Color(appState.themeManager.current.accentCG).opacity(0.3) :
                                          Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        appState.settings.activeClickType == type ?
                                        Color(appState.themeManager.current.accentCG) : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                        }
                    }
                    
                    labeledSlider(
                        label: "Icons per click",
                        value: Binding(
                            get: { Double(appState.settings.iconsPerClick) },
                            set: { appState.settings.iconsPerClick = Int($0) }
                        ),
                        range: 1...20, step: 1,
                        display: { "\(Int($0))" }
                    )
                    
                    Button("Clear Arena") { appState.clearArena() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
                
                Divider()
                
                // MARK: Seed
                sectionHeader("Seed (Repeat Matchup)")
                
                HStack {
                    Text("Seed").font(.callout)
                    Spacer()
                    TextField("Seed", value: $appState.settings.seed, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
                
                Text("Same seed + same settings = same battle every time.")
                    .font(.caption)
                    .opacity(0.7)
                
                Button("🔀 Shuffle Seed") { appState.shuffleSeed() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                
                HStack(spacing: 8) {
                    Button("Save Preset…") { appState.savePreset() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("Load Preset…") { appState.loadPreset() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
                
                if let err = appState.presetError {
                    Text(err).font(.caption).foregroundColor(.red)
                }
                
                Divider()
                
                // MARK: Arena
                sectionHeader("Arena")
                
                labeledSlider(
                    label: "Width",
                    value: $appState.settings.arenaWidth,
                    range: 220...520, step: 10,
                    display: { "\(Int($0))" }
                )
                .onChange(of: appState.settings.arenaWidth) { _ in appState.arenaResized() }
                
                labeledSlider(
                    label: "Height",
                    value: $appState.settings.arenaHeight,
                    range: 300...760, step: 10,
                    display: { "\(Int($0))" }
                )
                .onChange(of: appState.settings.arenaHeight) { _ in appState.arenaResized() }
                
                Divider()
                
                // MARK: Behavior
                sectionHeader("Behavior")
                
                labeledSlider(
                    label: "Speed",
                    value: $appState.settings.speed,
                    range: 0.1...5.0, step: 0.1,
                    display: { String(format: "%.1fx", $0) }
                )
                
                labeledSlider(
                    label: "Icon Size",
                    value: $appState.settings.iconSize,
                    range: 14...44, step: 1,
                    display: { "\(Int($0))" }
                )
                
                labeledSlider(
                    label: "Random Wobble",
                    value: $appState.settings.wobble,
                    range: 0...1.0, step: 0.05,
                    display: { String(format: "%.2f", $0) }
                )
                
                Toggle("Motion Trails", isOn: $appState.settings.trailsEnabled)
                Toggle("Sound Effects", isOn: $appState.settings.soundEnabled)
                
                Divider()
                
                // MARK: Finale
                sectionHeader("Finale")
                
                Toggle("Slow-mo + Zoom Finish", isOn: $appState.settings.finaleEnabled)
                
                if appState.settings.finaleEnabled {
                    labeledSlider(
                        label: "Kicks in at",
                        value: Binding(
                            get: { Double(appState.settings.finaleThreshold) },
                            set: { appState.settings.finaleThreshold = Int($0) }
                        ),
                        range: 4...40, step: 1,
                        display: { "\(Int($0))" }
                    )
                }
                
                Divider()
                
                // MARK: Export Settings
                sectionHeader("Recording / Export")
                
                HStack {
                    Text("FPS").font(.callout)
                    Spacer()
                    Picker("", selection: $appState.settings.exportFPS) {
                        ForEach([ExportFPS.fps30, ExportFPS.fps60], id: \.self) { fps in
                            Text(fps.displayName).tag(fps)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
                
                HStack {
                    Text("Max Duration").font(.callout)
                    Spacer()
                    Picker("", selection: $appState.settings.maxDuration) {
                        ForEach(MaxDuration.allPresets, id: \.displayName) { d in
                            Text(d.displayName).tag(d)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Toggle("3-2-1 Countdown", isOn: $appState.settings.countdownEnabled)
                Toggle("Auto-stop on Winner", isOn: $appState.settings.autoStopOnWinner)
                
                labeledSlider(
                    label: "Winner Hold",
                    value: $appState.settings.winnerHoldSeconds,
                    range: 0.5...5.0, step: 0.5,
                    display: { String(format: "%.1fs", $0) }
                )
                
                Divider()
                
                // MARK: Short-form Content
                sectionHeader("Short-Form / Socials")
                
                Toggle("Intro Fade-in", isOn: $appState.settings.introEnabled)
                if appState.settings.introEnabled {
                    labeledSlider(
                        label: "Intro Duration",
                        value: $appState.settings.introDurationSeconds,
                        range: 0.5...3.0, step: 0.5,
                        display: { String(format: "%.1fs", $0) }
                    )
                }
                
                HStack {
                    Text("Winner Text").font(.callout)
                    Spacer()
                    TextField("Auto", text: $appState.settings.customWinnerText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
                
                HStack {
                    Text("Winner Style").font(.callout)
                    Spacer()
                    Picker("", selection: $appState.settings.winnerDisplayStyle) {
                        ForEach(WinnerDisplayStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
                
                Toggle("Branding / Watermark", isOn: $appState.settings.brandingEnabled)
                if appState.settings.brandingEnabled {
                    HStack {
                        Text("Brand Text").font(.callout)
                        Spacer()
                        TextField("@YourHandle", text: $appState.settings.brandingText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                    }
                    labeledSlider(
                        label: "Opacity",
                        value: $appState.settings.brandingOpacity,
                        range: 0.1...1.0, step: 0.1,
                        display: { String(format: "%.0f%%", $0 * 100) }
                    )
                }
                
                Divider()
                
                // MARK: Theme
                sectionHeader("Theme")
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(ThemeName.allCases, id: \.self) { themeName in
                        let theme = ThemeManager.theme(for: themeName)
                        Button(themeName.displayName) {
                            appState.applyTheme(themeName)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color(theme.arenaCG))
                        .foregroundColor(Color(theme.textCG))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    appState.settings.theme == themeName ? Color.white : Color.clear,
                                    lineWidth: 2
                                )
                        )
                    }
                }
                
                Divider()
                
                // MARK: File Output
                sectionHeader("File Output")
                
                HStack {
                    Text("Prefix").font(.callout)
                    Spacer()
                    TextField("RPS_Battle", text: $appState.settings.filenamePrefix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Output Folder").font(.callout)
                        Text(appState.outputFolder.lastPathComponent)
                            .font(.caption)
                            .opacity(0.7)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Change…") { appState.pickOutputFolder() }
                        .buttonStyle(.bordered)
                }
                
                HStack(spacing: 8) {
                    Button("Open Folder") { appState.revealOutputFolder() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    if appState.lastExportedURL != nil {
                        Button("Reveal Last") { appState.revealLastExport() }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }
                }
                
                Divider()
                
                // MARK: Advanced
                DisclosureGroup("Advanced Physics", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 12) {
                        labeledSlider(
                            label: "Bounce Impulse",
                            value: $appState.settings.bounceStrength,
                            range: 0.1...2.0, step: 0.1,
                            display: { String(format: "%.1f", $0) }
                        )
                        labeledSlider(
                            label: "Min Speed",
                            value: $appState.settings.minSpeed,
                            range: 0.1...3.0, step: 0.1,
                            display: { String(format: "%.1f", $0) }
                        )
                        labeledSlider(
                            label: "Max Speed",
                            value: $appState.settings.maxSpeed,
                            range: 1.0...10.0, step: 0.5,
                            display: { String(format: "%.1f", $0) }
                        )
                    }
                    .padding(.top, 6)
                }
                
                Spacer(minLength: 20)
            }
            .padding(14)
        }
        .background(Color(appState.themeManager.current.panelCG))
    }
    
    // MARK: - Helpers
    
    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .opacity(0.6)
            .kerning(0.8)
    }
    
    @ViewBuilder
    private func labeledSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: @escaping (Double) -> String
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.callout)
                .frame(width: 105, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(display(value.wrappedValue))
                .font(.callout.monospacedDigit())
                .frame(width: 45, alignment: .trailing)
        }
    }
}
