//
//  DeviceCollectionViewCell.swift
//  ArtLight
//
//  Created by Jean Pierre on 9/2/18.
//  Copyright © 2018 Jean Pierre. All rights reserved.
//

import UIKit

class DeviceCollectionViewCell: UICollectionViewCell {
    
    var background: UIImageView = {
        let imageView = UIImageView(frame: .zero)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    var titleLabel: UILabel = {
        let label = UILabel(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = UIColor.white
        label.font = UIFont.boldSystemFont(ofSize: 13.0)
        return label
    }()
    
    var liveIndicator: DotIndicator = {
        let indicator = DotIndicator(frame:.zero)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.isLive = true
        return indicator
    }()
    
    private func setupSubviews() {
        self.contentView.addSubview(background)
        self.contentView.addSubview(titleLabel)
        self.contentView.addSubview(liveIndicator)
    }
    
    private func setupConstraints() {
        background.topAnchor.constraint(equalTo: contentView.topAnchor).isActive = true
        background.leftAnchor.constraint(equalTo: contentView.leftAnchor).isActive = true
        background.rightAnchor.constraint(equalTo: contentView.rightAnchor).isActive = true
        background.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).isActive = true
        
        liveIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4).isActive = true
        liveIndicator.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor, constant: 0).isActive = true
        liveIndicator.widthAnchor.constraint(equalToConstant: 8).isActive = true
        liveIndicator.heightAnchor.constraint(equalToConstant: 8).isActive = true
        
        titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5).isActive = true
        titleLabel.leadingAnchor.constraint(equalTo: liveIndicator.trailingAnchor, constant: 4).isActive = true
        titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5).isActive = true
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.setupCellLook()
        self.setupSubviews()
        self.setupConstraints()
    }
    
    private func setupCellLook() {
        self.contentView.layer.cornerRadius = 4.0
        self.contentView.layer.borderWidth = 1.0
        self.contentView.layer.borderColor = UIColor.clear.cgColor
        self.contentView.layer.masksToBounds = true;
        
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOffset = CGSize(width:0,height: 2.0)
        self.layer.shadowRadius = 2.0
        self.layer.shadowOpacity = 0.2
        self.layer.masksToBounds = false;
        self.layer.shadowPath = UIBezierPath(roundedRect:self.bounds, cornerRadius:self.contentView.layer.cornerRadius).cgPath
    }
    
    
    
    
}
