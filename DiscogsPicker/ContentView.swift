import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                .ignoresSafeArea()

                if viewModel.needsSetup {
                    SetupView(viewModel: viewModel)
                } else {
                    PickerView(viewModel: viewModel)
                }
            }
            .navigationTitle(showsNavigationChrome ? "Crate Shuffle" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showsNavigationChrome ? .visible : .hidden, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(.white)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Refresh Collection") {
                            Task { await viewModel.syncCollection() }
                        }
                        Button("Reset Credentials", role: .destructive) {
                            viewModel.signOut()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(viewModel.isSyncing)
                }
            }
            .task {
                await viewModel.runAutoRefreshLoop()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await viewModel.refreshCollectionIfPossible() }
            }
            .alert("Something went sideways", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var showsNavigationChrome: Bool {
        viewModel.needsSetup || verticalSizeClass != .compact
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}

private struct SetupView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pick from your shelves")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("A quick shuffle for the next spin.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.68))
                }

                VStack(spacing: 14) {
                    TextField(
                        text: $viewModel.credentials.username,
                        prompt: signInPrompt("Discogs username")
                    ) {
                        Text("Discogs username")
                    }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .submitLabel(.go)
                        .signInTextFieldStyle()

                    SecureField(
                        text: $viewModel.credentials.token,
                        prompt: signInPrompt("Personal Access Token")
                    ) {
                        Text("Personal access token")
                    }
                        .textContentType(.password)
                        .submitLabel(.go)
                        .signInTextFieldStyle()
                }
                .onSubmit(syncCollectionIfReady)

                personalAccessTokenHelp

                Button {
                    syncCollectionIfReady()
                } label: {
                    Label(viewModel.isSyncing ? "Syncing" : "Sync Collection", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                        .frame(minHeight: 50)
                        .background(viewModel.hasCredentials && !viewModel.isSyncing ? Color.blue : Color.white.opacity(0.16), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(viewModel.hasCredentials && !viewModel.isSyncing ? 0 : 0.22), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSyncing || !viewModel.hasCredentials)

                if viewModel.isSyncing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                discogsNotice
            }
            .padding(24)
            .frame(maxWidth: 520)
        }
    }

    private func syncCollectionIfReady() {
        guard viewModel.hasCredentials, !viewModel.isSyncing else { return }
        Task { await viewModel.syncCollection() }
    }

    @MainActor private var personalAccessTokenHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Use a Discogs personal access token, not your Discogs password.")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)

            Text("In Discogs, open Settings, then Developers, then copy your personal access token into the field above.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.72))

            Link(destination: URL(string: "https://www.discogs.com/settings/developers")!) {
                Label("Open Discogs Developer Settings", systemImage: "arrow.up.forward.square")
                    .font(.footnote.weight(.semibold))
            }
            .tint(.blue)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
    }
}

private func signInPrompt(_ text: String) -> Text {
    Text(text)
        .fontWeight(.semibold)
        .foregroundStyle(.white.opacity(0.58))
}

private extension View {
    func signInTextFieldStyle() -> some View {
        self
            .textFieldStyle(.plain)
            .foregroundStyle(.white)
            .tint(.blue)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            }
            .autocorrectionDisabled()
    }
}

private struct PickerView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                landscapeLayout(size: proxy.size)
            } else {
                portraitLayout(size: proxy.size)
            }
        }
        .background(Color.black)
    }

    private func portraitLayout(size: CGSize) -> some View {
        VStack(spacing: 18) {
            if let release = viewModel.currentRelease {
                SwipeNavigableReleaseView(viewModel: viewModel, release: release, slideDistance: size.width) { displayedRelease in
                    ArtworkView(
                        thumbnailURL: displayedRelease.basicInformation.thumbnailArtworkURL,
                        fullSizeURL: displayedRelease.basicInformation.fullArtworkURL
                    )
                    .frame(width: size.width, height: size.width)
                }
                .frame(width: size.width, height: size.width)

                metadata(for: release, textAlignment: .center, swipeDistance: max(size.width - 40, 1))
                    .padding(.horizontal, 20)
            }

            Spacer(minLength: 0)

            pickAnotherButton
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
    }

    private func landscapeLayout(size: CGSize) -> some View {
        let artworkSize = size.height
        let controlsWidth = min(max(size.width - artworkSize - 48, 160), 430)

        return HStack(alignment: .center, spacing: 24) {
            if let release = viewModel.currentRelease {
                SwipeNavigableReleaseView(viewModel: viewModel, release: release, slideDistance: artworkSize) { displayedRelease in
                    ArtworkView(
                        thumbnailURL: displayedRelease.basicInformation.thumbnailArtworkURL,
                        fullSizeURL: displayedRelease.basicInformation.fullArtworkURL
                    )
                    .frame(width: artworkSize, height: artworkSize)
                }
                .frame(width: artworkSize, height: artworkSize)

                VStack(alignment: .center, spacing: 24) {
                    ZStack {
                        Text("Crate Shuffle")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        HStack {
                            Spacer()
                            pickerMenu
                        }
                    }
                    .frame(maxWidth: controlsWidth)

                    Spacer(minLength: 0)

                    metadata(for: release, textAlignment: .center, swipeDistance: controlsWidth)
                        .frame(maxWidth: controlsWidth)

                    Spacer(minLength: 0)

                    pickAnotherButton
                        .frame(maxWidth: controlsWidth)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: artworkSize, alignment: .center)
                .padding(.trailing, 32)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
        .ignoresSafeArea(.container, edges: .vertical)
    }

    private var pickerMenu: some View {
        Menu {
            Button("Refresh Collection") {
                Task { await viewModel.syncCollection() }
            }
            Button("Reset Credentials", role: .destructive) {
                viewModel.signOut()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundStyle(.white)
        }
        .disabled(viewModel.isSyncing)
    }

    private func metadata(for release: CollectionRelease, textAlignment: TextAlignment, swipeDistance: CGFloat) -> some View {
        VStack(alignment: textAlignment == .leading ? .leading : .center, spacing: 8) {
            SwipeNavigableReleaseView(viewModel: viewModel, release: release, slideDistance: swipeDistance) { displayedRelease in
                releaseIdentity(for: displayedRelease, textAlignment: textAlignment)
            }

            Link(destination: release.discogsURL ?? URL(string: "https://www.discogs.com")!) {
                Text("Data provided by Discogs")
                    .font(.footnote.weight(.medium))
                    .underline()
            }
            .tint(.white.opacity(0.82))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: textAlignment == .leading ? .leading : .center)
    }

    private func releaseIdentity(for release: CollectionRelease, textAlignment: TextAlignment) -> some View {
        VStack(alignment: textAlignment == .leading ? .leading : .center, spacing: 8) {
            Text(release.basicInformation.title)
                .font(.title.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(textAlignment)
                .lineLimit(4)
                .minimumScaleFactor(0.76)

            Text(release.displayArtist)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(textAlignment)
        }
        .frame(maxWidth: .infinity, alignment: textAlignment == .leading ? .leading : .center)
        .contentShape(Rectangle())
    }

    private var pickAnotherButton: some View {
        Button {
            viewModel.chooseRandom()
        } label: {
            Label(viewModel.isPreparingNextRelease ? "Getting Next" : "Pick Another", systemImage: "shuffle")
                .frame(maxWidth: .infinity)
                .foregroundStyle(.white)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .controlSize(.large)
        .disabled(!viewModel.canPickAnother)
        .opacity(viewModel.canPickAnother ? 1 : 0.72)
    }
}

private enum RecordSwipeDirection {
    case backward
    case forward

    var completionOffsetSign: CGFloat {
        switch self {
        case .backward: 1
        case .forward: -1
        }
    }

    var targetStartOffsetSign: CGFloat {
        switch self {
        case .backward: -1
        case .forward: 1
        }
    }
}

private struct SwipeNavigableReleaseView<Content: View>: View {
    @ObservedObject var viewModel: AppViewModel
    let release: CollectionRelease
    let slideDistance: CGFloat
    @ViewBuilder var content: (CollectionRelease) -> Content

    @State private var dragOffset: CGFloat = 0
    @State private var targetRelease: CollectionRelease?
    @State private var swipeDirection: RecordSwipeDirection?
    @State private var isCompletingSwipe = false
    @State private var lockedRelease: CollectionRelease?

    private let swipeThreshold: CGFloat = 60
    private let unavailableDragLimit: CGFloat = 64
    private let bounceDistance: CGFloat = 24
    private let completionDuration = 0.22

    var body: some View {
        let visibleRelease = lockedRelease ?? release

        ZStack {
            if let targetRelease, let swipeDirection {
                content(targetRelease)
                    .offset(x: dragOffset + swipeDirection.targetStartOffsetSign * slideDistance)
            }

            content(visibleRelease)
                .offset(x: dragOffset)
        }
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        updateSwipe(translation: value.translation.width)
                    }
                    .onEnded { value in
                        finishSwipe(translation: value.translation.width)
                    }
            )
    }

    private func updateSwipe(translation: CGFloat) {
        guard !isCompletingSwipe else { return }

        let direction = swipeDirection ?? direction(for: translation)
        let target = targetRelease ?? targetRelease(for: direction)

        swipeDirection = direction
        targetRelease = target

        if target == nil {
            dragOffset = min(max(translation, -unavailableDragLimit), unavailableDragLimit)
        } else {
            dragOffset = min(max(translation, -slideDistance), slideDistance)
        }
    }

    private func finishSwipe(translation: CGFloat) {
        let direction = swipeDirection ?? direction(for: translation)
        let target = targetRelease ?? targetRelease(for: direction)

        guard abs(translation) >= swipeThreshold else {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                dragOffset = 0
            }
            resetTarget(after: 0.18)
            return
        }

        guard let target else {
            bounce(direction: direction)
            return
        }

        completeSwipe(direction: direction, target: target)
    }

    private func direction(for translation: CGFloat) -> RecordSwipeDirection {
        translation >= 0 ? .backward : .forward
    }

    private func targetRelease(for direction: RecordSwipeDirection) -> CollectionRelease? {
        switch direction {
        case .backward:
            viewModel.previousReleaseForNavigation
        case .forward:
            viewModel.nextReleaseForNavigation
        }
    }

    private func completeSwipe(direction: RecordSwipeDirection, target: CollectionRelease) {
        isCompletingSwipe = true
        lockedRelease = target

        withAnimation(.easeOut(duration: completionDuration)) {
            dragOffset = direction.completionOffsetSign * slideDistance
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + completionDuration) {
            let didNavigate = switch direction {
            case .backward:
                viewModel.navigateBack()
            case .forward:
                viewModel.navigateForward()
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragOffset = 0
                swipeDirection = nil
                isCompletingSwipe = false
            }

            if !didNavigate {
                lockedRelease = nil
                targetRelease = nil
                bounce(direction: direction)
            } else {
                targetRelease = nil
                clearLockedRelease(after: 0.05, remainingAttempts: 4)
            }
        }
    }

    private func bounce(direction: RecordSwipeDirection) {
        targetRelease = nil
        swipeDirection = direction

        withAnimation(.spring(response: 0.16, dampingFraction: 0.55)) {
            dragOffset = direction.completionOffsetSign * bounceDistance
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                dragOffset = 0
            }
            resetTarget(after: 0.2)
        }
    }

    private func resetTarget(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            targetRelease = nil
            swipeDirection = nil
            isCompletingSwipe = false
        }
    }

    private func clearLockedRelease(after delay: TimeInterval, remainingAttempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if release.instanceId == lockedRelease?.instanceId || remainingAttempts <= 0 {
                lockedRelease = nil
            } else {
                clearLockedRelease(after: delay, remainingAttempts: remainingAttempts - 1)
            }
        }
    }
}

private struct ArtworkView: View {
    let thumbnailURL: URL?
    let fullSizeURL: URL?

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let previewURL = thumbnailURL ?? fullSizeURL

            ZStack {
                AsyncImage(url: previewURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        placeholder(systemImage: "record.circle")
                    case .empty:
                        ProgressView()
                            .frame(width: size, height: size)
                    @unknown default:
                        placeholder(systemImage: "record.circle")
                    }
                }

                if let thumbnailURL, fullSizeURL != thumbnailURL {
                    AsyncImage(url: fullSizeURL) { phase in
                        if case let .success(image) = phase {
                            image
                                .resizable()
                                .scaledToFit()
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .background(Color.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func placeholder(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white.opacity(0.45))
            .padding(72)
    }
}

private var discogsNotice: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("This application uses Discogs' API but is not affiliated with, sponsored or endorsed by Discogs. 'Discogs' is a trademark of Zink Media, LLC.")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.68))

        Link("Data provided by Discogs", destination: URL(string: "https://www.discogs.com")!)
            .font(.footnote.weight(.medium))
    }
}
