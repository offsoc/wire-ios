//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import UIKit
import WireSyncEngine
import WireCommonComponents

final class ProfileHeaderViewController: UIViewController {

    /// The options to customize the appearance and behavior of the view.
    var options: Options {
        didSet {
            applyOptions()
        }
    }

    /// Associated conversation, if displayed in the context of a conversation
    let conversation: ZMConversation?

    /// The user that is displayed.
    private let user: UserType
    private var userStatus = UserStatus()

    private let userSession: UserSession
    private let isSelfUserProteusVerifiedUseCase: IsSelfUserProteusVerifiedUseCaseProtocol
    private let isSelfUserE2EICertifiedUseCase: IsSelfUserE2EICertifiedUseCaseProtocol

    /// The user who is viewing this view
    let viewer: UserType

    /// The current group admin status.
    var isAdminRole: Bool {
        didSet {
            groupRoleIndicator.isHidden = !self.isAdminRole
        }
    }

    var stackView: CustomSpacingStackView!

    typealias AccountPageStrings = L10n.Accessibility.AccountPage
    typealias LabelColors = SemanticColors.Label

    let nameLabel: DynamicFontLabel = {
        let label = DynamicFontLabel(fontSpec: .accountName,
                                     color: LabelColors.textDefault)
        label.accessibilityLabel = AccountPageStrings.Name.description
        label.accessibilityIdentifier = "name"

        label.setContentHuggingPriority(UILayoutPriority.required, for: .vertical)
        label.setContentCompressionResistancePriority(UILayoutPriority.required, for: .vertical)

        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        label.accessibilityTraits.insert(.header)
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 3
        label.textAlignment = .center

        return label
    }()

    let handleLabel = DynamicFontLabel(fontSpec: .mediumRegularFont,
                                       color: LabelColors.textDefault)
    let teamNameLabel = DynamicFontLabel(fontSpec: .accountTeam,
                                         color: LabelColors.textDefault)
    let remainingTimeLabel = DynamicFontLabel(fontSpec: .mediumSemiboldFont,
                                              color: LabelColors.textDefault)
    let imageView =  UserImageView(size: .big)
    let userStatusViewController: UserStatusViewController

    let guestIndicatorStack = UIStackView()
    let groupRoleIndicator = LabelIndicator(context: .groupRole)

    let guestIndicator = LabelIndicator(context: .guest)
    let externalIndicator = LabelIndicator(context: .external)
    let federatedIndicator = LabelIndicator(context: .federated)
    let warningView = WarningLabelView()

    private var userObserver: NSObjectProtocol?
    private var teamObserver: NSObjectProtocol?

    ///
    /// Creates a profile view for the specified user and options.
    /// - parameter user: The user to display the profile of.
    /// - parameter conversation: The conversation.
    /// - parameter options: The options for the appearance and behavior of the view.
    /// - parameter userSession: The user session.
    /// - parameter isSelfUserProteusVerifiedUseCase: Use case for getting the self user's Proteus verification status.
    /// - parameter isSelfUserE2EICertifiedUseCase: Use case for getting the self user's MLS verification status.
    /// Note: You can change the options later through the `options` property.
    init(
        user: UserType,
        viewer: UserType,
        conversation: ZMConversation?,
        options: Options,
        userSession: UserSession,
        isSelfUserProteusVerifiedUseCase: IsSelfUserProteusVerifiedUseCaseProtocol,
        isSelfUserE2EICertifiedUseCase: IsSelfUserE2EICertifiedUseCaseProtocol
    ) {
        self.user = user
        self.userSession = userSession
        self.isSelfUserProteusVerifiedUseCase = isSelfUserProteusVerifiedUseCase
        self.isSelfUserE2EICertifiedUseCase = isSelfUserE2EICertifiedUseCase
        isAdminRole = conversation.map(self.user.isGroupAdmin) ?? false
        self.viewer = viewer
        self.conversation = conversation
        self.options = options
        self.userStatusViewController = .init(
            options: options.contains(.allowEditingAvailability) ? [.allowSettingStatus] : [.hideActionHint],
            settings: .shared
        )

        super.init(nibName: nil, bundle: nil)

        userStatusViewController.delegate = self
        userStatusViewController.userStatus = .init(
            user: user,
            isCertified: false // TODO [WPB-765]: provide value after merging into `epic/e2ei`
        )
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        imageView.isAccessibilityElement = true
        imageView.accessibilityElementsHidden = false
        imageView.accessibilityIdentifier = "user image"
        imageView.setImageConstraint(resistance: 249, hugging: 750)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        imageView.initialsFont = .systemFont(ofSize: 55, weight: .semibold).monospaced()
        imageView.userSession = userSession
        imageView.user = user

        if !ProcessInfo.processInfo.isRunningTests, let session = userSession as? ZMUserSession {
            userObserver = UserChangeInfo.add(observer: self, for: user, in: session)
        }

        handleLabel.accessibilityLabel = AccountPageStrings.Handle.description
        handleLabel.accessibilityIdentifier = "username"
        handleLabel.setContentHuggingPriority(UILayoutPriority.required, for: .vertical)
        handleLabel.setContentCompressionResistancePriority(UILayoutPriority.required, for: .vertical)

        let nameHandleStack = UIStackView(arrangedSubviews: [nameLabel, handleLabel])
        nameHandleStack.axis = .vertical
        nameHandleStack.alignment = .center
        nameHandleStack.spacing = 2

        teamNameLabel.accessibilityLabel = AccountPageStrings.TeamName.description
        teamNameLabel.accessibilityIdentifier = "team name"
        teamNameLabel.setContentHuggingPriority(UILayoutPriority.required, for: .vertical)
        teamNameLabel.setContentCompressionResistancePriority(UILayoutPriority.required, for: .vertical)

        userStatus.name = user.name ?? ""
        updateNameLabel()

        let remainingTimeString = user.expirationDisplayString
        remainingTimeLabel.text = remainingTimeString
        remainingTimeLabel.isHidden = remainingTimeString == nil

        guestIndicatorStack.addArrangedSubview(guestIndicator)
        guestIndicatorStack.addArrangedSubview(remainingTimeLabel)
        guestIndicatorStack.spacing = 12
        guestIndicatorStack.axis = .vertical
        guestIndicatorStack.alignment = .center

        updateGuestIndicator()
        updateExternalIndicator()
        updateFederatedIndicator()
        updateGroupRoleIndicator()
        updateHandleLabel()
        updateTeamLabel()

        addChild(userStatusViewController)

        stackView = CustomSpacingStackView(
            customSpacedArrangedSubviews: [
                nameHandleStack,
                teamNameLabel,
                imageView,
                userStatusViewController.view,
                guestIndicatorStack,
                externalIndicator,
                federatedIndicator,
                groupRoleIndicator,
                warningView
            ]
        )

        stackView.alignment = .center
        stackView.axis = .vertical

        stackView.wr_addCustomSpacing(32, after: nameHandleStack)
        stackView.wr_addCustomSpacing(32, after: teamNameLabel)
        stackView.wr_addCustomSpacing(24, after: imageView)
        stackView.wr_addCustomSpacing(20, after: guestIndicatorStack)
        stackView.wr_addCustomSpacing(20, after: externalIndicator)
        stackView.wr_addCustomSpacing(20, after: federatedIndicator)

        view.addSubview(stackView)

        guestIndicator.tintColor = SemanticColors.Icon.foregroundDefault
        view.backgroundColor = UIColor.clear

        configureConstraints()
        applyOptions()

        userStatusViewController.didMove(toParent: self)

        if let team = user.membership?.team {
            teamObserver = TeamChangeInfo.add(observer: self, for: team)
        }
        view.backgroundColor = UIColor.clear
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        Task {
            do {
                userStatus.isCertified = try await isSelfUserE2EICertifiedUseCase.invoke()
                userStatus.isVerified = await isSelfUserProteusVerifiedUseCase.invoke()
            } catch {
                WireLogger.e2ei.error("failed to get self user's verification status: \(String(reflecting: error))")
            }
            updateNameLabel()
        }
    }

    private func configureConstraints() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let leadingSpaceConstraint = stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40)
        let topSpaceConstraint = stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20)
        let trailingSpaceConstraint = stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        let bottomSpaceConstraint = stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)

        let widthImageConstraint = imageView.widthAnchor.constraint(lessThanOrEqualToConstant: 164)
        NSLayoutConstraint.activate([
            // stackView
            widthImageConstraint, leadingSpaceConstraint, topSpaceConstraint, trailingSpaceConstraint, bottomSpaceConstraint
        ])
    }

    private func updateGuestIndicator() {
        if let conversation = conversation {
            guestIndicatorStack.isHidden = !user.isGuest(in: conversation)
        } else {
            guestIndicatorStack.isHidden = !viewer.isTeamMember || viewer.canAccessCompanyInformation(of: user)
        }
    }

    private func updateExternalIndicator() {
        externalIndicator.isHidden = !user.isExternalPartner
    }

    private func updateFederatedIndicator() {
        federatedIndicator.isHidden = !user.isFederated
    }

    private func updateGroupRoleIndicator() {
        let groupRoleIndicatorHidden: Bool
        switch conversation?.conversationType {
        case .group?:
            groupRoleIndicatorHidden = !(conversation.map(user.isGroupAdmin) ?? false)
        default:
            groupRoleIndicatorHidden = true
        }
        groupRoleIndicator.isHidden = groupRoleIndicatorHidden

    }

    private func applyOptions() {
        nameLabel.isHidden = options.contains(.hideUsername)
        updateHandleLabel()
        updateTeamLabel()
        updateImageButton()
        updateAvailabilityVisibility()
        warningView.update(withUser: user)
    }

    private func updateNameLabel() {
        defer { nameLabel.accessibilityValue = nameLabel.text }
        guard !userStatus.name.isEmpty else { return nameLabel.text = "" }

        nameLabel.attributedText = [
            .init(string: userStatus.name),
            // MLS verified shield
            !userStatus.isCertified ? nil : .init(attachment: .init(image: Asset.Images.certificateValid.image)),
            // Proteus verified shield
            !userStatus.isVerified ? nil : .init(attachment: .init(image: Asset.Images.verifiedShield.image))
        ].compactMap { $0 }.joined(separator: .init(string: " "))
    }

    private func updateHandleLabel() {
        if let handle = user.handle, !handle.isEmpty, !options.contains(.hideHandle) {
            handleLabel.text = "@" + handle
            handleLabel.accessibilityValue = handleLabel.text
        } else {
            handleLabel.isHidden = true
        }
    }

    private func updateTeamLabel() {
        if let teamName = user.teamName, !options.contains(.hideTeamName) {
            teamNameLabel.text = teamName
            teamNameLabel.accessibilityValue = teamNameLabel.text
            teamNameLabel.isHidden = false
        } else {
            teamNameLabel.isHidden = true
        }
    }

    private func updateAvailabilityVisibility() {
        let isHidden = options.contains(.hideAvailability) || !options.contains(.allowEditingAvailability) && user.availability == .none
        userStatusViewController.view?.isHidden = isHidden
    }

    private func updateImageButton() {
        if options.contains(.allowEditingProfilePicture) {
            imageView.accessibilityLabel = AccountPageStrings.ProfilePicture.description
            imageView.accessibilityHint = AccountPageStrings.ProfilePicture.hint
            imageView.accessibilityTraits = .button
            imageView.isUserInteractionEnabled = true
        } else {
            imageView.accessibilityLabel = AccountPageStrings.ProfilePicture.description
            imageView.accessibilityTraits = [.image]
            imageView.isUserInteractionEnabled = false
        }
    }

    // MARK: -

    /// The options to customize the appearance and behavior of the view.
    struct Options: OptionSet {

        let rawValue: Int

        /// Whether to hide the username of the user.
        static let hideUsername = Options(rawValue: 1 << 0)

        /// Whether to hide the handle of the user.
        static let hideHandle = Options(rawValue: 1 << 1)

        /// Whether to hide the availability status of the user.
        static let hideAvailability = Options(rawValue: 1 << 2)

        /// Whether to hide the team name of the user.
        static let hideTeamName = Options(rawValue: 1 << 3)

        /// Whether to allow the user to change their availability.
        static let allowEditingAvailability = Options(rawValue: 1 << 4)

        /// Whether to allow the user to change their availability.
        static let allowEditingProfilePicture = Options(rawValue: 1 << 5)

    }
}

// MARK: - UserStatusViewControllerDelegate

extension ProfileHeaderViewController: UserStatusViewControllerDelegate {

    func userStatusViewController(_ viewController: UserStatusViewController, didSelect availability: Availability) {
        guard viewController === userStatusViewController else { return }

        userSession.perform { [weak self] in
            self?.user.availability = availability
        }
    }
}

// MARK: - ZMUserObserving

extension ProfileHeaderViewController: UserObserving {

    func userDidChange(_ changeInfo: UserChangeInfo) {
        if changeInfo.nameChanged {
            userStatus.name = changeInfo.user.name ?? ""
            updateNameLabel()
        }
        if changeInfo.handleChanged {
            updateHandleLabel()
        }
        if changeInfo.availabilityChanged {
            updateAvailabilityVisibility()
        }
    }
}

// MARK: - TeamObserver

extension ProfileHeaderViewController: TeamObserver {

    func teamDidChange(_ changeInfo: TeamChangeInfo) {
        if changeInfo.nameChanged {
            updateTeamLabel()
        }
    }
}
