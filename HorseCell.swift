//
//  HorseCell.swift
//  horse race
//
//  Created by Frankie Docking Smith on 21/12/2024.
//

import UIKit

class HorseCell: UITableViewCell {
    
    @IBOutlet weak var horseImageView: UIImageView! // To display the horse's image
    
    @IBOutlet weak var horseNameLabel: UILabel! // To display the horse's name
    
    @IBOutlet weak var horseScoreLabel: UILabel! // To display the horse's score

    func configure(with horseName: String, score: Double, image: UIImage?) {
        horseNameLabel.text = horseName
        horseScoreLabel.text = "Score: \(String(format: "%.2f", score))"
        horseImageView.image = image
    }
}
