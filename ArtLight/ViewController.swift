//
//  ViewController.swift
//  ArtLight
//
//  Created by Jean Pierre on 8/31/18.
//  Copyright © 2018 Jean Pierre. All rights reserved.
//

import UIKit


class ViewController: UIViewController {
    
    @IBOutlet weak var backgroundImageView: UIImageView!
    

    override func viewDidLoad() {
        super.viewDidLoad()
        
        getBackgroundImage()
        // Do any additional setup after loading the view, typically from a nib.
        
//        ParticleCloud.sharedInstance().login(withUser: "airllcpr@gmail.com", password: "Stevejobs@4848") { (error:Error?) -> Void in
//            if let _ = error {
//                print("Wrong credentials or no internet connectivity, please try again")
//            }
//            else {
//
//                print("Logged in")
//            }
//        }
//
//        var myPhoton : ParticleDevice?
//        ParticleCloud.sharedInstance().getDevices { (devices:[ParticleDevice]?, error:Error?) -> Void in
//            if let _ = error {
//                print("Check your internet connectivity")
//            }
//            else {
//
//                if let d = devices {
//                    for device in d {
//
//                        if device.name == "myNewPhotonName" {
//                            myPhoton = device
//                        }
//                    }
//                }
//            }
//        }
    }
    
    func getBackgroundImage() {
        let url = URL(string: "https://source.unsplash.com/featured/?abstract,art")
            URLSession.shared.dataTask(with: url!, completionHandler: { (data, response, error) in
                if error != nil { print(error!); return}
                DispatchQueue.main.async {
                    self.backgroundImageView.image = UIImage(data: data!)
                }
            }).resume()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

