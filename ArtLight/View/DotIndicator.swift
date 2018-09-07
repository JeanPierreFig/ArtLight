//
//  LiveIndicator.swift
//  ArtLight
//
//  Created by Jean Pierre on 9/6/18.
//  Copyright © 2018 Jean Pierre. All rights reserved.
//

import UIKit

class DotIndicator: UIView {
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init(frame: CGRect) {
        self.isLive = true
        super.init(frame: frame)
    }
    override func layoutSubviews() {
        self.layer.cornerRadius = self.bounds.width / 2
    }
    
    var isLive: Bool {
        didSet {
            if isLive == true {
                self.backgroundColor = UIColor.init(red:52/255 , green: 152/255, blue: 219/255, alpha: 1)
                self.pulsate()
            }
            else {
                self.backgroundColor = UIColor.lightGray
            }
        }
    }
    
    private func pulsate () {
        UIView.animate(withDuration: 2.0, delay:0, options: [.repeat, .autoreverse], animations: {
            self.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            self.alpha = 0.5
        }, completion: {completion in
            self.transform = CGAffineTransform(scaleX: 1, y: 1)
            self.alpha = 1
        })
    }
    
}
