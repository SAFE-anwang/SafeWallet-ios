import SwiftUI
import RxSwift

@MainActor
final class SuperNodeListObservable: ObservableObject {
    @Published private(set) var state: SuperNodeViewModel.State
    @Published private(set) var searchCaution: Caution?
    @Published private(set) var isLoadingMore = false

    let viewModel: SuperNodeViewModel

    private let disposeBag = DisposeBag()

    init(viewModel: SuperNodeViewModel) {
        self.viewModel = viewModel
        state = viewModel.state

        subscribe(disposeBag, viewModel.stateDriver) { [weak self] state in
            self?.state = state
        }

        subscribe(disposeBag, viewModel.searchCautionDriver) { [weak self] caution in
            self?.searchCaution = caution
        }

        subscribe(disposeBag, viewModel.isLoadingMoreDriver) { [weak self] isLoadingMore in
            self?.isLoadingMore = isLoadingMore
        }
    }

    var type: SuperNodeModule.SuperNodeType {
        viewModel.type
    }

    var nodeType: Safe4NodeType {
        viewModel.nodeType
    }

    var address: String {
        viewModel.address
    }

    func refresh() {
        viewModel.refresh()
    }

    func softRefresh() {
        viewModel.softRefresh()
    }

    func loadMore() {
        viewModel.loadMore()
    }

    func search(text: String?) {
        viewModel.search(text: text)
    }

    var canLoadMore: Bool {
        viewModel.canLoadMore
    }

}

struct SuperNodeListView: View {
    @ObservedObject private var observable: SuperNodeListObservable
    @State private var searchText = ""

    init(observable: SuperNodeListObservable) {
        _observable = ObservedObject(wrappedValue: observable)
    }

    var body: some View {
        ThemeView(style: .list) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch observable.state {
        case .loading:
            if case let .completed(items) = observable.viewModel.state, !items.isEmpty {
                listContent(items: items)
            } else {
                ScrollableThemeView {
                    VStack(spacing: .margin12) {
                        headerBlock(items: [])
                        ProgressView()
                            .tint(.themeJacob)
                            .padding(.top, .margin32)
                    }
                    .padding(.horizontal, .margin16)
                    .padding(.top, .margin12)
                    .padding(.bottom, .margin32)
                }
            }
        case let .completed(items):
            listContent(items: items)
        case let .searchResults(items):
            listContent(items: items)
        case .failed:
            PlaceholderViewNew(icon: "warning_filled", subtitle: "sync_error".localized)
                .padding(.horizontal, .margin16)
        }
    }

    private func listContent(items: [SuperNodeViewModel.ViewItem]) -> some View {
        ScrollableThemeView {
            LazyVStack(spacing: .margin12) {
                headerBlock(items: items)

                if items.isEmpty {
                    PlaceholderViewNew(icon: "safe4_empty", title: "safe_zone.safe4.empty.description".localized)
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.cacheIdentity) { index, item in
                        SuperNodeSwiftUICard(
                            item: item,
                            rank: observable.type == .All ? index + 1 : nil,
                            onTap: { presentDetail(item, viewType: .Detail) },
                            onJoin: { presentDetail(item, viewType: .JoinPartner) },
                            onVote: { presentDetail(item, viewType: .Vote) },
                            onEdit: { presentChange(item) },
                            onAddLock: { presentAddLock(item) }
                        )
                    }
                }

                if shouldShowLoadMoreTrigger {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            observable.loadMore()
                        }
                }

                if observable.isLoadingMore {
                    ProgressView()
                        .tint(.themeJacob)
                        .padding(.vertical, .margin12)
                }

                if shouldShowNoMoreFooter(items: items) {
                    Text("loadData.nomore".localized)
                        .themeSubhead2(color: .themeGray, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, .margin12)
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.top, .margin12)
            .padding(.bottom, .margin32)
        }
        .refreshable {
            observable.softRefresh()
        }
    }

    private var shouldShowLoadMoreTrigger: Bool {
        guard case .completed = observable.state else {
            return false
        }

        return observable.canLoadMore && !observable.isLoadingMore
    }

    private func shouldShowNoMoreFooter(items: [SuperNodeViewModel.ViewItem]) -> Bool {
        guard observable.type == .All else {
            return false
        }
        guard case .completed = observable.state else {
            return false
        }
        guard !items.isEmpty else {
            return false
        }

        return !observable.canLoadMore && !observable.isLoadingMore
    }

    @ViewBuilder
    private func headerBlock(items: [SuperNodeViewModel.ViewItem]) -> some View {
        VStack(spacing: .margin12) {
            if observable.type == .All {
                searchBar
            }

            infoBanner(
                text: "safe_zone.safe4.vote.type.locked.recoard.tips".localized,
                iconColor: .themeJacob
            )

            if observable.nodeType != .normal {
                infoBanner(
                    text: observable.nodeType.warnings,
                    iconColor: .themeLucian
                )
            }

            if case .failed = observable.state, items.isEmpty == false {
                infoBanner(
                    text: "sync_error".localized,
                    iconColor: .themeLucian
                )
            }
        }
    }

    private var searchBar: some View {
        VStack(spacing: .margin8) {
            HStack(spacing: .margin8) {
                HStack(spacing: .margin8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.themeGray)

                    TextField("safe_zone.safe4.node.super.search.tips".localized, text: $searchText)
                        .font(.themeBody)
                        .foregroundStyle(Color.themeLeah)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            observable.search(text: searchText)
                        }
                }
                .padding(.horizontal, .margin16)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.themeLawrence)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.themeBlade, lineWidth: 1)
                )

                Button {
                    observable.search(text: searchText)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.themeGray)
                        .frame(width: 56, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.themeLawrence)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.themeBlade, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            if let caution = observable.searchCaution {
                Text(caution.text)
                    .themeCaption(color: caution.type == .error ? .themeLucian : .themeGray, alignment: .leading)
                    .padding(.horizontal, .margin4)
            }
        }
    }

    private func infoBanner(text: String, iconColor: Color) -> some View {
        HStack(alignment: .top, spacing: .margin12) {
            Image(systemName: "info.circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(iconColor)
                .padding(.top, 2)

            Text(text)
                .themeSubhead1(color: .themeLeah, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin16)
        .modifier(ThemeListStyleModifier(themeListStyle: .lawrence, cornerRadius: 22))
    }

    private func presentDetail(_ item: SuperNodeViewModel.ViewItem, viewType: SuperNodeDetailViewModel.ViewType) {
        guard let viewModel = SuperNodeDetailModule.viewModel(viewItem: item) else { return }
        Coordinator.shared.present { _ in
            SuperNodeDetailView(viewModel: viewModel, viewType: viewType)
        }
    }

    private func presentChange(_ item: SuperNodeViewModel.ViewItem) {
        guard let viewModel = SuperNodeChangeModule.viewModel(viewItem: item) else { return }
        Coordinator.shared.present { _ in
            SuperNodeChangeView(viewModel: viewModel)
        }
    }

    private func presentAddLock(_ item: SuperNodeViewModel.ViewItem) {
        let ids = item.info.founders
            .filter { $0.addr.address.lowercased() == observable.address.lowercased() }
            .map(\.lockID)

        guard let viewModel = AddLockDaysModule.viewModel(ids: ids) else { return }
        Coordinator.shared.present { _ in
            AddLockDaysView(viewModel: viewModel)
        }
    }
}

private struct SuperNodeSwiftUICard: View {
    let item: SuperNodeViewModel.ViewItem
    let rank: Int?
    let onTap: () -> Void
    let onJoin: () -> Void
    let onVote: () -> Void
    let onEdit: () -> Void
    let onAddLock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .margin12) {
            detailSection
            actionRow
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin16)
        .modifier(ThemeListStyleModifier(themeListStyle: .lawrence, cornerRadius: 24))
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: .margin6) {
            header
            content
            progressSection
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: .margin8) {
            VStack(alignment: .leading, spacing: .margin8) {
                if let rank {
                    Text("safe_zone.safe4.ranking".localized + "\(rank)")
                        .themeHeadline2(color: .themeLeah, alignment: .leading)
                }

                Text("safe_zone.safe4.node".localized + "ID: \(item.info.id.description)")
                    .themeSubhead1(color: .themeLeah, alignment: .leading)
            }

            Spacer(minLength: .margin8)

            statusBadge(text: item.nodeState.title, color: Color(item.nodeState.color))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: .margin8) {
            Text("safe_zone.node_name".localized + item.info.name)
                .themeSubhead1(color: .themeLeah, alignment: .leading)

            HStack(alignment: .center, spacing: .margin8) {
                Text("safe_zone.safe4.node.address".localized + truncatedText(item.info.addr.address, maxLength: 20))
                    .themeSubhead1(color: item.ownerType == .None ? .themeLeah : Color(UIColor.themeIssykBlue), alignment: .leading)

                if item.ownerType != .None, item.ownerType != .Owner {
                    statusBadge(text: item.ownerType.title, color: Color(UIColor.themeIssykBlue))
                }
            }

            HStack(alignment: .top, spacing: .margin12) {
                Text("safe_zone.votes".localized + item.totalVoteNum.safe4FomattedAmount)
                    .themeSubhead1(color: .themeLeah, alignment: .leading)

                Text("safe_zone.stake_amount".localized + "\(item.totalAmount.safe4FomattedAmount) SAFE")
                    .themeSubhead1(color: .themeLeah, alignment: .trailing)
                    .fixedSize()
            }
        }
    }

    private var progressSection: some View {
        HStack(spacing: .margin8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.themeBlade)

                    Capsule(style: .continuous)
                        .fill(Color.themeJacob)
                        .frame(width: max(10, proxy.size.width * progressValue))
                }
            }
            .frame(height: 8)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text((item.rate * 100).safe4FormattedAmount + "%")
                    .themeHeadline2(color: .themeLeah, alignment: .trailing)
            }
            .fixedSize()
        }
    }

    private var actionRow: some View {
        HStack(spacing: .margin8) {
            actionButton(
                title: "safe_zone.safe4.node.join.partner".localized,
                isEnabled: item.isEnabledJoin,
                style: item.isEnabledJoin ? .yellowGradient : .gray,
                action: onJoin
            )

            actionButton(
                title: "safe_zone.vote".localized,
                isEnabled: item.isEnabledVote,
                style: item.isEnabledVote ? .yellowGradient : .gray,
                action: onVote
            )

            actionButton(
                title: "safe_zone.safe4.node.edit".localized,
                isEnabled: item.isEnabledEdit && item.ownerType == .Creator,
                style: item.isEnabledEdit && item.ownerType == .Creator ? .yellowGradient : .gray,
                action: onEdit
            )

            actionButton(
                title: "safe_zone.safe4.node.locked.days.add.title".localized,
                isEnabled: item.isEnabledAddLockDay,
                style: item.isEnabledAddLockDay ? .yellowGradient : .gray,
                action: onAddLock
            )
        }
    }

    private func actionButton(title: String, isEnabled: Bool, style: PrimaryButtonStyle.Style, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .font(.themeSubhead1)
                .foregroundStyle(buttonForegroundColor(isEnabled: isEnabled, style: style))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(buttonBackground(isEnabled: isEnabled, style: style))
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .textCaptionSB(color: Color(uiColor: .themeWhite))
            .padding(.horizontal, .margin10)
            .padding(.vertical, .margin6)
            .background(
                Capsule(style: .continuous)
                    .fill(color)
            )
    }

    private func truncatedText(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let start = text.prefix(maxLength / 2)
        let end = text.suffix(maxLength / 2)
        return "\(start)...\(end)"
    }

    private var progressValue: CGFloat {
        let value = (item.rate as NSDecimalNumber).doubleValue
        return min(max(value, 0), 1)
    }

    private func buttonForegroundColor(isEnabled: Bool, style: PrimaryButtonStyle.Style) -> Color {
        guard isEnabled else {
            return .themeAndy
        }

        switch style {
        case .yellow, .yellowGradient:
            return .themeDark
        case .gray, .red, .transparent:
            return .themeClaude
        }
    }

    @ViewBuilder
    private func buttonBackground(isEnabled: Bool, style: PrimaryButtonStyle.Style) -> some View {
        if isEnabled, style == .yellowGradient {
            LinearGradient(
                gradient: Gradient(colors: [Color(hex: 0xFFD000), Color(hex: 0xFFA800)]),
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Capsule(style: .continuous)
                .fill(isEnabled ? Color.themeLeah : Color.themeBlade)
        }
    }
}
