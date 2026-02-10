import SwiftUI
import SceneKit

struct CreateNFTView: View {
    @EnvironmentObject var auctionService: AuctionService
    @EnvironmentObject var lang: LanguageManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var title = ""
    @State private var description = ""
    @State private var category: NFTArtwork.ArtworkCategory = .digitalPainting
    @State private var startingPrice = ""
    @State private var durationHours: Double = 24
    @State private var blockchain: NFTArtwork.BlockchainNetwork = .polygon

    @State private var currentStep: CreateStep = .upload
    @State private var isProcessing = false
    @State private var showPreview3D = false
    @State private var showSuccess = false

    enum CreateStep: Int, CaseIterable {
        case upload = 0
        case details = 1
        case preview = 2
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Step indicator
                stepIndicator
                    .padding()

                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        switch currentStep {
                        case .upload:
                            uploadStep
                        case .details:
                            detailsStep
                        case .preview:
                            previewStep
                        }
                    }
                    .padding()
                }

                // Navigation buttons
                navigationButtons
                    .padding()
            }
            .navigationTitle(L10n.createNFT)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $selectedImage)
            }
            .alert(L10n.nftCreated, isPresented: $showSuccess) {
                Button(L10n.viewFeed) { dismiss() }
            } message: {
                Text(L10n.nftLiveMessage(title))
            }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(CreateStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 8) {
                    Circle()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.nftPurple : Color(.tertiarySystemFill))
                        .frame(width: 28, height: 28)
                        .overlay {
                            if step.rawValue < currentStep.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(step.rawValue + 1)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(step.rawValue <= currentStep.rawValue ? .white : .secondary)
                            }
                        }

                    if step.rawValue < CreateStep.allCases.count - 1 {
                        Rectangle()
                            .fill(step.rawValue < currentStep.rawValue ? Color.nftPurple : Color(.tertiarySystemFill))
                            .frame(height: 2)
                    }
                }
            }
        }
    }

    // MARK: - Upload Step

    private var uploadStep: some View {
        VStack(spacing: 20) {
            Text(L10n.uploadArtwork)
                .font(NFTTypography.title2)

            Text(L10n.selectImageDescription)
                .font(NFTTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let image = selectedImage {
                // Preview selected image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.2), radius: 10)

                Button {
                    showImagePicker = true
                } label: {
                    Label(L10n.changeImage, systemImage: "photo.on.rectangle")
                        .font(NFTTypography.subheadline)
                }
            } else {
                // Upload area
                Button {
                    showImagePicker = true
                } label: {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 50))
                            .foregroundStyle(.nftPurple)

                        VStack(spacing: 4) {
                            Text(L10n.tapToSelect)
                                .font(NFTTypography.headline)
                            Text("PNG, JPG up to 50MB")
                                .font(NFTTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .foregroundStyle(Color.nftPurple.opacity(0.4))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Details Step

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.artworkDetails)
                .font(NFTTypography.title2)

            // Title
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.title)
                    .font(NFTTypography.subheadline)
                    .fontWeight(.medium)
                TextField(L10n.enterTitle, text: $title)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Description
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.description)
                    .font(NFTTypography.subheadline)
                    .fontWeight(.medium)
                TextField(L10n.describeArtwork, text: $description, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Category
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.category)
                    .font(NFTTypography.subheadline)
                    .fontWeight(.medium)
                Picker(L10n.category, selection: $category) {
                    ForEach(NFTArtwork.ArtworkCategory.allCases) { cat in
                        Label(L10n.categoryName(cat), systemImage: cat.iconName)
                            .tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Blockchain
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.blockchain)
                    .font(NFTTypography.subheadline)
                    .fontWeight(.medium)
                Picker(L10n.blockchain, selection: $blockchain) {
                    ForEach(NFTArtwork.BlockchainNetwork.allCases, id: \.self) { net in
                        Text(net.rawValue).tag(net)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Starting Price
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.startingPriceLabel)
                    .font(NFTTypography.subheadline)
                    .fontWeight(.medium)
                HStack {
                    TextField("0.01", text: $startingPrice)
                        .textFieldStyle(.plain)
                        .keyboardType(.decimalPad)
                    Text("ETH")
                        .font(NFTTypography.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Duration
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.auctionDuration(Int(durationHours)))
                    .font(NFTTypography.subheadline)
                    .fontWeight(.medium)
                Slider(value: $durationHours, in: 1...168, step: 1)
                    .tint(.nftPurple)
                HStack {
                    Text("1h")
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("7 days")
                        .font(NFTTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Preview Step

    private var previewStep: some View {
        VStack(spacing: 20) {
            Text(L10n.preview3D)
                .font(NFTTypography.title2)

            Text(L10n.convertedTo3D)
                .font(NFTTypography.body)
                .foregroundStyle(.secondary)

            if let image = selectedImage {
                // 3D Preview
                Artwork3DView(
                    artwork: NFTArtwork(
                        title: title,
                        artistName: auctionService.currentUser.displayName,
                        description: description,
                        imageName: "preview",
                        category: category
                    ),
                    artworkImage: image
                )
                .frame(height: 350)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .nftCardStyle()
            }

            // Summary
            VStack(spacing: 12) {
                summaryRow(L10n.title, value: title)
                summaryRow(L10n.category, value: L10n.categoryName(category))
                summaryRow(L10n.blockchain, value: blockchain.rawValue)
                summaryRow(L10n.startingPriceLabel, value: "\(startingPrice) ETH")
                summaryRow("Duration", value: "\(Int(durationHours)) hours")
            }
            .padding()
            .nftCardStyle()
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(NFTTypography.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(NFTTypography.subheadline)
                .fontWeight(.medium)
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep != .upload {
                Button {
                    withAnimation {
                        currentStep = CreateStep(rawValue: currentStep.rawValue - 1) ?? .upload
                    }
                } label: {
                    Text(L10n.back)
                        .font(NFTTypography.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            Button {
                if currentStep == .preview {
                    createNFT()
                } else {
                    withAnimation {
                        currentStep = CreateStep(rawValue: currentStep.rawValue + 1) ?? .preview
                    }
                }
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(currentStep == .preview ? L10n.createNFT : L10n.next)
                        .font(NFTTypography.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canProceed ? LinearGradient.nftPrimary : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canProceed || isProcessing)
        }
    }

    private var canProceed: Bool {
        switch currentStep {
        case .upload:
            return selectedImage != nil
        case .details:
            return !title.isEmpty && !startingPrice.isEmpty && (Double(startingPrice) ?? 0) > 0
        case .preview:
            return true
        }
    }

    private func createNFT() {
        guard let image = selectedImage,
              let price = Double(startingPrice) else { return }

        isProcessing = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            _ = auctionService.createNFTFromImage(
                image: image,
                title: title,
                description: description,
                category: category,
                startingPrice: price,
                durationHours: durationHours
            )
            isProcessing = false
            showSuccess = true
        }
    }
}
