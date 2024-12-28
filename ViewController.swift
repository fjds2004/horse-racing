import UIKit
import PDFKit
import Vision
import VisionKit

// MARK: - Horse Struct
struct Horse {
    let name: String
    let age: Int
    let weight: Double
    let lastWeight: Double
    let jockeyRating: Double?
    let trainerRating: Double?
    let previousPerformance: [(position: Int, ground: String)]
    let distance: Double
}

// MARK: - TrackCondition Enum
enum TrackCondition: String, CaseIterable {
    case good = "Gd"
    case soft = "Sft"
    case heavy = "Hy"
    case firm = "Fm"
    case standard = "St"
}

// MARK: - ViewController
class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate {
    @IBOutlet weak var tableView: UITableView!
    var horses: [Horse] = []
    var predictedHorses: [(horse: Horse, score: Double)] = []
    var selectedTrackCondition: TrackCondition = .good

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.dataSource = self
        tableView.delegate = self
    }

    @IBAction func uploadPDFButtonTapped(_ sender: UIButton) {
        let alertController = UIAlertController(
            title: "Upload File",
            message: "Please select the type of file to upload:",
            preferredStyle: .actionSheet
        )

        alertController.addAction(UIAlertAction(title: "PDF", style: .default) { _ in
            let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
            documentPicker.delegate = self
            self.present(documentPicker, animated: true, completion: nil)
        })

        alertController.addAction(UIAlertAction(title: "Image", style: .default) { _ in
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            imagePicker.sourceType = .photoLibrary
            self.present(imagePicker, animated: true, completion: nil)
        })

        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alertController, animated: true, completion: nil)
    }

    // MARK: - Track Condition Prompt
    func askForTrackCondition(completion: @escaping (TrackCondition) -> Void) {
        let alertController = UIAlertController(
            title: "Track Condition",
            message: "Please select the current track condition:",
            preferredStyle: .alert
        )

        for condition in TrackCondition.allCases {
            alertController.addAction(UIAlertAction(title: condition.rawValue, style: .default) { _ in
                completion(condition)
            })
        }

        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alertController, animated: true, completion: nil)
    }

    // MARK: - PDF Parsing
    func parsePDF(at fileURL: URL) {
        guard let document = PDFDocument(url: fileURL) else {
            showAlert(title: "Error", message: "Failed to load PDF document.")
            return
        }

        var extractedText = ""
        for pageIndex in 0..<document.pageCount {
            if let page = document.page(at: pageIndex), let pageContent = page.string {
                extractedText.append(pageContent)
                extractedText.append("\n") // Add a newline between pages
            }
        }

        if extractedText.isEmpty {
            showAlert(title: "Error", message: "Failed to extract text from PDF.")
            return
        }

        processExtractedData(extractedText)
    }

    func processExtractedData(_ extractedText: String) {
        horses = parseHorseData(from: extractedText)

        guard !horses.isEmpty else {
            showAlert(title: "No Data", message: "No valid horse data found.")
            return
        }

        askForTrackCondition { [weak self] trackCondition in
            guard let self = self else { return }
            self.selectedTrackCondition = trackCondition

            self.predictedHorses = self.predictHorses(horses: self.horses, trackCondition: trackCondition)
            self.predictedHorses.sort { $0.score > $1.score } // Sort by score in descending order

            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - Horse Data Parsing
    func parseHorseData(from text: String) -> [Horse] {
        var horses: [Horse] = []
        let lines = text.split(separator: "\n")
        var currentHorseDetails: [String] = []

        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || line.contains("ATR VERDICT") {
                continue
            }

            if let firstCharacter = line.trimmingCharacters(in: .whitespacesAndNewlines).first, firstCharacter.isNumber {
                if !currentHorseDetails.isEmpty {
                    if let horse = parseHorseDetails(from: currentHorseDetails) {
                        horses.append(horse)
                    }
                }
                currentHorseDetails = [String(line)]
            } else {
                currentHorseDetails.append(String(line))
            }
        }

        if !currentHorseDetails.isEmpty {
            if let horse = parseHorseDetails(from: currentHorseDetails) {
                horses.append(horse)
            }
        }

        return horses
    }

    func parseHorseDetails(from lines: [String]) -> Horse? {
        guard let firstLine = lines.first else { return nil }
        
        // Extract name from the line
        let name = extractHorseName(from: firstLine)
        
        // Extract other details
        // This assumes the age and weight are in a consistent format
        let age = Int(lines.last?.split(separator: " ").last ?? "") ?? 0
        let weight = Double(firstLine.split(separator: " ").last?.replacingOccurrences(of: "kg", with: "") ?? "") ?? 0.0

        // Parse previous performance from form (e.g., "21-1161")
        var previousPerformance: [(position: Int, ground: String)] = []
        if lines.count > 1 {
            let formLine = lines[1]
            previousPerformance = parsePreviousPerformance(from: formLine)
        }

        return Horse(
            name: name,
            age: age,
            weight: weight,
            lastWeight: weight, // Adjust if there is separate data for last weight
            jockeyRating: nil, // Replace with actual parsing logic
            trainerRating: nil, // Replace with actual parsing logic
            previousPerformance: previousPerformance,
            distance: 0.0 // Replace with actual parsing logic
        )
    }
    
    func extractHorseName(from text: String) -> String {
        // Assuming horse names are in bold, you might need to adjust this based on actual data
        let components = text.split(separator: " ")
        return components.dropFirst(1).joined(separator: " ")
    }

    func parsePreviousPerformance(from text: String) -> [(position: Int, ground: String)] {
        var performance: [(position: Int, ground: String)] = []
        let races = text.split(separator: " ")
        for race in races {
            let position = Int(race.trimmingCharacters(in: .letters)) ?? 0
            let ground = String(race.filter { $0.isLetter })
            performance.append((position: position, ground: ground))
        }
        return performance
    }

    // MARK: - Prediction Logic
    func calculateScore(for horse: Horse, trackCondition: TrackCondition) -> Double {
        let ageAdjustment = calculateAgeAdjustment(age: horse.age, distance: horse.distance)
        let weightAdjustment = calculateWeightChangeAdjustment(currentWeight: horse.weight, lastWeight: horse.lastWeight)
        let avgPerformance = averagePerformance(onGround: trackCondition.rawValue, previousPerformances: horse.previousPerformance)
        let weatherAdjustment = calculateWeatherAdjustment(avgPerformance: avgPerformance)

        print("Calculating for \(horse.name): AgeAdj=\(ageAdjustment), WeightAdj=\(weightAdjustment), AvgPerf=\(avgPerformance ?? 0), WeatherAdj=\(weatherAdjustment)")

        let score = (
            ageAdjustment +
            -1.0 * horse.weight +
            2.0 * (horse.jockeyRating ?? 0.0) +
            2.0 * (horse.trainerRating ?? 0.0) +
            (-3.0 * (avgPerformance ?? 0.0))
        ) * weightAdjustment * weatherAdjustment

        print("Final score for \(horse.name): \(score)")
        return score
    }

    func predictHorses(horses: [Horse], trackCondition: TrackCondition) -> [(horse: Horse, score: Double)] {
        return horses.map { ($0, calculateScore(for: $0, trackCondition: trackCondition)) }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: - Utility Functions
    func calculateAgeAdjustment(age: Int, distance: Double) -> Double {
        let ageDouble = Double(age)
        if ageDouble <= 2 { return 0 }
        if ageDouble <= 4.5 { return (ageDouble - 2) / (4.5 - 2) * (distance < 1 ? 10 : 15) }
        return (distance < 1 ? 10 : 15) - (ageDouble - 4.5) / 5 * (distance < 1 ? 6 : 9.5)
    }

    func calculateWeightChangeAdjustment(currentWeight: Double, lastWeight: Double) -> Double {
        return currentWeight > lastWeight ? 1.19 : 1.0
    }

    func calculateWeatherAdjustment(avgPerformance: Double?) -> Double {
        guard let avg = avgPerformance else { return 1.0 }
        if avg <= 3 { return 1.2 }
        if avg <= 6 { return 1.0 }
        return 0.8
    }

    func averagePerformance(onGround ground: String, previousPerformances: [(position: Int, ground: String)]) -> Double? {
        let performancesOnGround = previousPerformances.filter { $0.ground == ground }
        guard !performancesOnGround.isEmpty else { return nil }
        let totalPositions = performancesOnGround.reduce(0) { $0 + $1.position }
        return Double(totalPositions) / Double(performancesOnGround.count)
    }

    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    // MARK: - Document Picker Delegate
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let selectedFileURL = urls.first else {
            showAlert(title: "Error", message: "No file was selected.")
            return
        }

        if selectedFileURL.startAccessingSecurityScopedResource() {
            defer { selectedFileURL.stopAccessingSecurityScopedResource() }
            parsePDF(at: selectedFileURL)
        } else {
            showAlert(title: "Error", message: "The app does not have permission to access this file.")
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("Document picker was cancelled.")
    }

    // MARK: - TableView Data Source
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return predictedHorses.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HorseCell", for: indexPath)
        let prediction = predictedHorses[indexPath.row]
        
        cell.textLabel?.text = "\(prediction.horse.name): \(String(format: "%.2f", prediction.score))"
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.lineBreakMode = .byWordWrapping
        return cell
    }
}

// Extension for image picker and text recognition
extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true, completion: nil)
        if let selectedImage = info[.originalImage] as? UIImage {
            extractText(from: selectedImage)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }

    func extractText(from image: UIImage) {
        guard let cgImage = image.cgImage else {
            showAlert(title: "Error", message: "Failed to get CGImage from selected image.")
            return
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { [weak self] (request, error) in
            guard let self = self else { return }
            if let error = error {
                self.showAlert(title: "Error", message: "Failed to recognize text: \(error.localizedDescription)")
                return
            }

            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let extractedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            self.processExtractedData(extractedText)
        }

        do {
            try requestHandler.perform([request])
        } catch {
            showAlert(title: "Error", message: "Failed to perform text recognition: \(error.localizedDescription)")
        }
    }
}
