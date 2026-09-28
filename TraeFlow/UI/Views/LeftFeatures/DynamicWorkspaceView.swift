import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum DynamicWorkspaceRoute: String, CaseIterable, Identifiable {
    case today
    case tasks
    case requirements
    case notes
    case ai
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "今日"
        case .tasks: return "待办"
        case .requirements: return "需求"
        case .notes: return "随笔"
        case .ai: return "AI"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "rectangle.grid.2x2.fill"
        case .tasks: return "checklist"
        case .requirements: return "point.3.connected.trianglepath.dotted"
        case .notes: return "square.and.pencil"
        case .ai: return "sparkles"
        case .settings: return "gearshape.fill"
        }
    }
}

/// 灵动岛工作台：悬停是一条短胶囊，点击才进入紧凑工作台。
struct DynamicWorkspaceView: View {
    var compactPreview = false
    var onModalInteractionStateChanged: (Bool) -> Void = { _ in }
    @State private var route: DynamicWorkspaceRoute = .today

    var body: some View {
        Group {
            if compactPreview {
                DynamicWorkspacePeekView()
            } else {
                HStack(spacing: 0) {
                    navigationRail.frame(width: 58)
                    Divider().overlay(Color.white.opacity(0.07))
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(DynamicVisualTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: DynamicVisualTheme.outerRadius, style: .continuous))
    }

    private var navigationRail: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().fill(DynamicVisualTheme.neonGradient)
                Image(systemName: "island.2").font(.system(size: 14, weight: .bold))
            }
            .frame(width: 32, height: 32)
            .padding(.top, 12)
            .padding(.bottom, 5)

            ForEach(DynamicWorkspaceRoute.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { route = item }
                } label: {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(route == item ? .white : .secondary)
                        .background(route == item ? DynamicVisualTheme.elevatedCard : .clear, in: RoundedRectangle(cornerRadius: 11))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .strokeBorder(route == item ? DynamicVisualTheme.orange : .clear, lineWidth: 1.2)
                        }
                }
                .buttonStyle(.plain)
                .help(item.title)
            }

            Spacer(minLength: 4)

            Button {
                NSWorkspace.shared.open(DynamicUserStoragePaths.rootURL)
            } label: {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("打开桌面灵动岛文件夹")
            .padding(.bottom, 10)
        }
        .background(Color.white.opacity(0.025))
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .today: DynamicTodayDashboardView(route: $route)
        case .tasks:
            PersonalTaskBoardView(
                expanded: true,
                onModalInteractionStateChanged: onModalInteractionStateChanged
            )
        case .requirements:
            RequirementManagerView(onModalInteractionStateChanged: onModalInteractionStateChanged)
        case .notes: PersonalNotesView()
        case .ai: DynamicAIAgentView()
        case .settings: PersonalWorkspaceSettingsView()
        }
    }
}

private struct DynamicWorkspacePeekView: View {
    @ObservedObject private var workspace = DynamicPersonalWorkspaceStore.shared
    @ObservedObject private var weather = DynamicWeatherStore.shared
    @ObservedObject private var recorder = DynamicQuickRecorder.shared
    @ObservedObject private var nowPlaying = NowPlayingProvider.shared

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(DynamicVisualTheme.neonGradient)
                Image(systemName: "island.2").font(.system(size: 15, weight: .bold))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                Text("今天还有 \(unfinishedCount) 件事")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }

            Divider().frame(height: 34).overlay(Color.white.opacity(0.1))

            Label(weather.rainProbability >= 40 ? "可能有雨，记得带伞" : "\(weather.temperatureText) · \(weather.conditionText)", systemImage: weather.systemImage)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(DynamicVisualTheme.cyan)
                .lineLimit(1)

            Spacer(minLength: 4)

            Button { recorder.toggleRecording() } label: {
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .frame(width: 30, height: 30)
                    .foregroundStyle(recorder.isRecording ? DynamicVisualTheme.orange : .white)
                    .background(DynamicVisualTheme.elevatedCard, in: Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "music.note")
                Text(nowPlaying.nowPlaying?.title ?? "音乐").lineLimit(1)
                Button { nowPlaying.togglePlayPause() } label: {
                    Image(systemName: nowPlaying.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .dynamicSurface(radius: 12, elevated: true)
        }
        .padding(.horizontal, 16)
        .onAppear {
            weather.refresh()
            if !nowPlaying.isStarted { nowPlaying.start() }
        }
    }

    private var unfinishedCount: Int { workspace.tasks.filter { $0.stage != .done }.count }
}

private struct DynamicTodayDashboardView: View {
    @Binding var route: DynamicWorkspaceRoute
    @ObservedObject private var workspace = DynamicPersonalWorkspaceStore.shared
    @ObservedObject private var weather = DynamicWeatherStore.shared
    @ObservedObject private var requirements = RequirementManagementStore.shared
    @ObservedObject private var recorder = DynamicQuickRecorder.shared
    @ObservedObject private var nowPlaying = NowPlayingProvider.shared
    @State private var showsForecast = false

    var body: some View {
        VStack(spacing: 10) {
            header
            insightStrip
            HStack(spacing: 10) {
                focusTasks
                VStack(spacing: 10) {
                    requirementCard
                    recorderCard
                    Spacer(minLength: 0)
                    musicCard
                }
                .frame(width: 222)
            }
        }
        .padding(12)
        .background(DynamicVisualTheme.canvas)
        .onAppear {
            weather.refresh()
            if !nowPlaying.isStarted { nowPlaying.start() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                Text(greeting).font(.system(size: 17, weight: .bold, design: .rounded))
            }
            Spacer()
            Button {
                showsForecast.toggle()
                if weather.forecastDays.isEmpty { weather.refresh() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: weather.systemImage)
                    Text("\(weather.cityName) · \(weather.temperatureText) · \(weather.conditionText)")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .rotationEffect(.degrees(showsForecast ? 180 : 0))
                }
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(DynamicVisualTheme.cyan)
                .padding(.horizontal, 11)
                .frame(height: 34)
            }
            .buttonStyle(.plain)
            .dynamicSurface(radius: 12, elevated: true)
            .popover(isPresented: $showsForecast, arrowEdge: .top) {
                SevenDayWeatherView()
            }
            Button { route = .settings } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .dynamicSurface(radius: 10, elevated: true)
        }
    }

    private var insightStrip: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DynamicVisualTheme.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 今日建议").font(.system(size: 10, weight: .semibold))
                Text(aiAdvice).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            ForEach(PersonalTaskStage.allCases) { stage in
                HStack(spacing: 4) {
                    Circle().fill(stage == .done ? Color.green : DynamicVisualTheme.cyan).frame(width: 5, height: 5)
                    Text("\(stage.title) \(workspace.tasks(in: stage).count)")
                }
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .dynamicSurface(radius: 14, elevated: true)
    }

    private var focusTasks: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日焦点").font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("只显示最值得先做的 3 件事").font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { route = .tasks } label: {
                    Label("全部待办", systemImage: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DynamicVisualTheme.cyan)
            }

            if priorityTasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 24)).foregroundStyle(DynamicVisualTheme.cyan)
                    Text("今天很清爽，先记下一件重要的事吧").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(priorityTasks) { task in
                    HStack(spacing: 9) {
                        Image(systemName: task.stage.systemImage)
                            .foregroundStyle(task.priority == .high ? DynamicVisualTheme.orange : DynamicVisualTheme.cyan)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                            Text(task.dueDate?.formatted(date: .abbreviated, time: .shortened) ?? task.stage.title)
                                .font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            ForEach(PersonalTaskStage.allCases) { stage in
                                Button(stage.title) { workspace.moveTask(id: task.id, to: stage) }
                            }
                        } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary) }
                        .menuStyle(.borderlessButton)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 48)
                    .dynamicSurface(radius: 13, elevated: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dynamicSurface(radius: 16)
    }

    private var requirementCard: some View {
        Button { route = .requirements } label: {
            HStack(spacing: 9) {
                Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(DynamicVisualTheme.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("需求管理").font(.system(size: 10, weight: .semibold))
                    Text(requirementSummary).font(.system(size: 8.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text("\(requirements.requirements.count)").font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .padding(11)
        }
        .buttonStyle(.plain)
        .dynamicSurface(radius: 14, elevated: true)
    }

    private var recorderCard: some View {
        HStack(spacing: 9) {
            Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
                .foregroundStyle(recorder.isRecording ? DynamicVisualTheme.orange : DynamicVisualTheme.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("快速录音").font(.system(size: 10, weight: .semibold))
                Text(recorder.isRecording ? elapsedText : recorder.statusText).font(.system(size: 8.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { recorder.toggleRecording() } label: {
                Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle").font(.system(size: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .dynamicSurface(radius: 14, elevated: true)
    }

    private var musicCard: some View {
        HStack(spacing: 9) {
            Group {
                if let artwork = nowPlaying.nowPlaying?.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
                else { Image(systemName: "music.note").foregroundStyle(DynamicVisualTheme.violet) }
            }
            .frame(width: 30, height: 30)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.nowPlaying?.title ?? "Mac 音乐").font(.system(size: 9.5, weight: .semibold)).lineLimit(1)
                Text(nowPlaying.nowPlaying?.artist ?? "等待播放").font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 2)
            Button { nowPlaying.togglePlayPause() } label: {
                Image(systemName: nowPlaying.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .dynamicSurface(radius: 14, elevated: true)
    }

    private var priorityTasks: [PersonalTask] {
        workspace.tasks
            .filter { $0.stage != .done }
            .sorted {
                let lhs = $0.priority == .high ? 0 : ($0.priority == .normal ? 1 : 2)
                let rhs = $1.priority == .high ? 0 : ($1.priority == .normal ? 1 : 2)
                if lhs != rhs { return lhs < rhs }
                return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
            .prefix(3)
            .map { $0 }
    }

    private var requirementSummary: String {
        guard let latest = requirements.requirements.first else { return "还没有需求" }
        return "\(latest.title) · \(latest.isLaunched ? "已上线" : latest.currentStage.title)"
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 { return "早上好，先抓住一件重要的事" }
        if hour < 18 { return "下午好，保持轻盈地推进" }
        return "晚上好，收好今天的进展"
    }

    private var aiAdvice: String {
        let unfinished = workspace.tasks.filter { $0.stage != .done }
        let weatherAdvice = weather.rainProbability >= 40 ? "今天可能有雨，出门记得带伞。" : "今天降雨概率不高。"
        guard let first = priorityTasks.first else { return weatherAdvice + " 当前没有待办。" }
        return weatherAdvice + " 还有 \(unfinished.count) 项未完成，建议先做“\(first.title)”。"
    }

    private var elapsedText: String {
        String(format: "正在录音 · %02d:%02d", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60)
    }
}

private struct SevenDayWeatherView: View {
    @ObservedObject private var weather = DynamicWeatherStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(weather.cityName) · 未来 7 天")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("包含今天，温度与降雨概率会随定位更新")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { weather.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .dynamicSurface(radius: 9, elevated: true)
            }

            if weather.forecastDays.isEmpty {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(weather.errorMessage ?? "正在获取最近七天天气…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                HStack(spacing: 7) {
                    ForEach(Array(weather.forecastDays.prefix(7).enumerated()), id: \.element.id) { index, day in
                        VStack(spacing: 7) {
                            Text(index == 0 ? "今天" : day.date.formatted(.dateTime.weekday(.short)))
                                .font(.system(size: 9, weight: .semibold))
                            Image(systemName: day.systemImage)
                                .symbolRenderingMode(.hierarchical)
                                .font(.system(size: 17))
                                .foregroundStyle(index == 0 ? DynamicVisualTheme.orange : DynamicVisualTheme.cyan)
                            Text("\(day.maximumTemperature)° / \(day.minimumTemperature)°")
                                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            Label("\(day.rainProbability)%", systemImage: "drop.fill")
                                .font(.system(size: 7.5))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            index == 0 ? DynamicVisualTheme.elevatedCard : DynamicVisualTheme.card,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(index == 0 ? DynamicVisualTheme.orange.opacity(0.78) : Color.white.opacity(0.06))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 570)
        .background(DynamicVisualTheme.canvas)
        .preferredColorScheme(.dark)
    }
}

private struct PersonalTaskBoardView: View {
    let expanded: Bool
    var onModalInteractionStateChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var workspace = DynamicPersonalWorkspaceStore.shared
    @State private var isAddingTask = false
    @State private var draggedTaskID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(expanded ? "待办管理" : "今日任务流")
                        .font(.system(size: expanded ? 18 : 13, weight: .bold, design: .rounded))
                    Text("拖动任务卡即可改变阶段")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isAddingTask = true
                } label: {
                    Label("新建", systemImage: "plus")
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                }
                .buttonStyle(.plain)
                .dynamicSurface(radius: 10, focused: true, elevated: true)
            }

            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(PersonalTaskStage.allCases) { stage in
                        taskColumn(stage)
                            .frame(width: max(120, (proxy.size.width - 24) / 4))
                    }
                }
            }
        }
        .padding(expanded ? 18 : 12)
        .background(DynamicVisualTheme.canvas)
        .sheet(isPresented: $isAddingTask) {
            AddPersonalTaskSheet(isPresented: $isAddingTask)
        }
        .onChange(of: isAddingTask) { _, isPresented in
            onModalInteractionStateChanged(isPresented)
        }
        .onDisappear {
            if isAddingTask {
                onModalInteractionStateChanged(false)
            }
        }
    }

    private func taskColumn(_ stage: PersonalTaskStage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: stage.systemImage)
                    .foregroundStyle(stage == .done ? Color.green : DynamicVisualTheme.cyan)
                Text(stage.title)
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer()
                Text("\(workspace.tasks(in: stage).count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(workspace.tasks(in: stage)) { task in
                        taskCard(task)
                            .onDrag {
                                draggedTaskID = task.id
                                return NSItemProvider(object: task.id as NSString)
                            }
                    }
                }
            }
            .scrollIndicators(.hidden)

            if workspace.tasks(in: stage).isEmpty {
                Text("拖到这里")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .dynamicSurface(radius: 15)
        .onDrop(
            of: [UTType.text],
            delegate: PersonalTaskStageDropDelegate(
                stage: stage,
                draggedTaskID: $draggedTaskID,
                onMove: workspace.moveTask
            )
        )
    }

    private func taskCard(_ task: PersonalTask) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 5) {
                Circle()
                    .fill(priorityColor(task.priority))
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
                Text(task.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            if let due = task.dueDate {
                Text(due.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundStyle(due < Date() && task.stage != .done ? DynamicVisualTheme.orange : Color.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicSurface(radius: 11, elevated: true)
        .contextMenu {
            Menu("移动到") {
                ForEach(PersonalTaskStage.allCases) { stage in
                    Button(stage.title) { workspace.moveTask(id: task.id, to: stage) }
                }
            }
            Button("删除", role: .destructive) { workspace.deleteTask(id: task.id) }
        }
    }

    private func priorityColor(_ priority: PersonalTaskPriority) -> Color {
        switch priority {
        case .low: return .secondary
        case .normal: return DynamicVisualTheme.cyan
        case .high: return DynamicVisualTheme.orange
        }
    }
}

private struct AddPersonalTaskSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var workspace = DynamicPersonalWorkspaceStore.shared
    @State private var title = ""
    @State private var detail = ""
    @State private var stage: PersonalTaskStage = .inbox
    @State private var priority: PersonalTaskPriority = .normal
    @State private var hasDueDate = false
    @State private var dueDate = Date().addingTimeInterval(3600)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建待办")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            TextField("任务名称", text: $title)
            TextField("补充说明（可选）", text: $detail)
            Picker("阶段", selection: $stage) {
                ForEach(PersonalTaskStage.allCases) { Text($0.title).tag($0) }
            }
            Picker("优先级", selection: $priority) {
                ForEach(PersonalTaskPriority.allCases) { Text($0.title).tag($0) }
            }
            Toggle("设置截止时间和系统提醒", isOn: $hasDueDate)
            if hasDueDate {
                DatePicker("截止时间", selection: $dueDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
            }
            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                Button("创建") {
                    _ = workspace.addTask(
                        title: title,
                        detail: detail,
                        stage: stage,
                        priority: priority,
                        dueDate: hasDueDate ? dueDate : nil
                    )
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(DynamicVisualTheme.orange)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(DynamicVisualTheme.card)
        .preferredColorScheme(.dark)
    }
}

private struct PersonalNotesView: View {
    @ObservedObject private var workspace = DynamicPersonalWorkspaceStore.shared
    @State private var selectedNoteID: String?
    @State private var searchText = ""
    @State private var title = ""
    @State private var markdown = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Text("随笔")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Spacer()
                    Button {
                        selectedNoteID = nil
                        title = ""
                        markdown = ""
                    } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                }
                TextField("搜索", text: $searchText)
                    .textFieldStyle(.plain)
                    .padding(9)
                    .dynamicSurface(radius: 10, elevated: true)
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(filteredNotes) { note in
                            Button {
                                selectedNoteID = note.id
                                title = note.title
                                markdown = note.markdown
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                                    Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 8)).foregroundStyle(.secondary)
                                }
                                .padding(9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .dynamicSurface(radius: 11, focused: selectedNoteID == note.id, elevated: true)
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: 220)

            Divider().overlay(Color.white.opacity(0.06))

            VStack(alignment: .leading, spacing: 12) {
                TextField("AI 自动标题", text: $title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .textFieldStyle(.plain)
                TextEditor(text: $markdown)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .dynamicSurface(radius: 14, elevated: true)
                HStack {
                    if let id = selectedNoteID {
                        Button("归档") { workspace.toggleArchiveNote(id: id) }
                        Button("删除", role: .destructive) {
                            workspace.deleteNote(id: id)
                            selectedNoteID = nil
                            title = ""
                            markdown = ""
                        }
                    }
                    Spacer()
                    Button("保存") { saveNote() }
                        .buttonStyle(.borderedProminent)
                        .tint(DynamicVisualTheme.orange)
                }
            }
            .padding(18)
        }
        .background(DynamicVisualTheme.canvas)
    }

    private var filteredNotes: [PersonalNote] {
        workspace.notes
            .filter { !$0.isArchived }
            .filter {
                searchText.isEmpty
                    || $0.title.localizedCaseInsensitiveContains(searchText)
                    || $0.markdown.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func saveNote() {
        if let id = selectedNoteID {
            workspace.updateNote(id: id, title: title, markdown: markdown)
        } else if let note = workspace.addNote(markdown: markdown) {
            selectedNoteID = note.id
            title = note.title
        }
    }
}

private struct PersonalWorkspaceSettingsView: View {
    @ObservedObject private var workspace = DynamicPersonalWorkspaceStore.shared
    @ObservedObject private var weather = DynamicWeatherStore.shared
    @ObservedObject private var reminders = DynamicReminderStore.shared
    @State private var city = ""
    @State private var backupMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("工作台设置")
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                settingsSection("天气与位置", symbol: "location.fill") {
                    HStack {
                        TextField("手动城市；留空则自动定位", text: $city)
                        Button("应用") { weather.useManualCity(city) }
                        Button("恢复自动定位") {
                            city = ""
                            weather.requestAutomaticLocation()
                        }
                    }
                }

                settingsSection("提醒权限", symbol: "bell.fill") {
                    HStack {
                        Text(reminders.notificationStatusText)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("请求权限") { reminders.requestNotificationPermission() }
                    }
                }

                settingsSection("首页组件", symbol: "rectangle.3.group.fill") {
                    VStack(spacing: 8) {
                        ForEach(workspace.modulePreferences.sorted(by: { $0.order < $1.order })) { preference in
                            HStack {
                                Text(preference.module.title)
                                Spacer()
                                Picker("尺寸", selection: Binding(
                                    get: { preference.size },
                                    set: { workspace.setModuleSize(preference.module, size: $0) }
                                )) {
                                    ForEach(WorkspaceModuleSize.allCases) { Text($0.title).tag($0) }
                                }
                                .labelsHidden()
                                .frame(width: 92)
                                Toggle("显示", isOn: Binding(
                                    get: { !preference.isHidden },
                                    set: { workspace.setModuleHidden(preference.module, hidden: !$0) }
                                ))
                                .toggleStyle(.switch)
                            }
                        }
                        HStack {
                            Spacer()
                            Button("恢复默认布局") { workspace.resetModuleLayout() }
                        }
                    }
                }

                settingsSection("数据与备份", symbol: "externaldrive.fill") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("文件位置：~/Desktop/灵动岛")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack {
                            Text(backupMessage.isEmpty ? (workspace.migrationMessage ?? "需求、随笔、录音与截图均保存在这里") : backupMessage)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer()
                            Button("打开文件夹") {
                                NSWorkspace.shared.open(workspace.userStorageRootURL)
                            }
                            Button("立即备份") {
                                backupMessage = workspace.createManualBackup().map { "已备份到 \($0.lastPathComponent)" } ?? "备份失败"
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("打开完整系统设置") { SettingsWindowController.shared.present() }
                }
            }
            .padding(20)
        }
        .background(DynamicVisualTheme.canvas)
        .onAppear { city = weather.manualCity }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
            content()
                .font(.system(size: 10.5))
        }
        .padding(15)
        .dynamicSurface(radius: 16, elevated: true)
    }
}

private struct PersonalTaskStageDropDelegate: DropDelegate {
    let stage: PersonalTaskStage
    @Binding var draggedTaskID: String?
    let onMove: (String, PersonalTaskStage) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedTaskID else { return }
        onMove(draggedTaskID, stage)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTaskID = nil
        return true
    }
}

private struct WorkspaceModuleDropDelegate: DropDelegate {
    let target: WorkspaceModule
    @Binding var draggedModule: WorkspaceModule?
    let onMove: (WorkspaceModule, WorkspaceModule) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedModule, draggedModule != target else { return }
        onMove(draggedModule, target)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedModule = nil
        return true
    }
}
