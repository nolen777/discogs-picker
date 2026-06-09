import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
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
            .navigationTitle("Discogs Picker")
            .navigationBarTitleDisplayMode(.inline)
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
                    TextField("Discogs username", text: $viewModel.credentials.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .submitLabel(.next)
                        .signInTextFieldStyle()

                    SecureField("Personal access token", text: $viewModel.credentials.token)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .signInTextFieldStyle()
                }

                personalAccessTokenHelp

                Button {
                    Task { await viewModel.syncCollection() }
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
}

private var personalAccessTokenHelp: some View {
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
            VStack(spacing: 18) {
                if let release = viewModel.currentRelease {
                    ArtworkView(
                        thumbnailURL: release.basicInformation.thumbnailArtworkURL,
                        fullSizeURL: release.basicInformation.fullArtworkURL
                    )
                        .frame(width: proxy.size.width, height: proxy.size.width)

                    VStack(spacing: 8) {
                        Text(release.basicInformation.title)
                            .font(.title.bold())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.76)

                        Text(release.displayArtist)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                }

                Spacer(minLength: 0)

                VStack(spacing: 12) {
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
                .padding(.horizontal, 20)
                .padding(.bottom, 30)

                if let release = viewModel.currentRelease {
                    Link(destination: release.discogsURL ?? URL(string: "https://www.discogs.com")!) {
                        Text("Data provided by Discogs")
                            .font(.footnote.weight(.medium))
                    }
                    .tint(.white.opacity(0.82))
                    .padding(.bottom, 8)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.black)
        }
        .background(Color.black)
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
