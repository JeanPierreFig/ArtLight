//
//  device.swift
//  ArtLight
//
//  Created by Jean Pierre on 9/3/18.
//  Copyright © 2018 Jean Pierre. All rights reserved.
//

import Foundation

class Device {
    var particalDevice: ParticleDevice
    let imageName: String
    let title: String
    var color: LightColor
    
    init(particalDevice: ParticleDevice, imageName: String, title: String, color: LightColor) {
        self.particalDevice = particalDevice
        self.imageName = imageName
        self.title = title
        self.color = color
    }
}


