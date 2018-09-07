//
//  ViewController.swift
//  ArtLight
//
//  Created by Jean Pierre on 8/31/18.
//  Copyright © 2018 Jean Pierre. All rights reserved.
//

import UIKit

private let reuseIdentifier = "device_cell"


class ViewController: UIViewController {
    
    var collectionView: UICollectionView = {
        let layout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()
        layout.sectionInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        layout.itemSize = CGSize(width: 130, height: 175)
        
        let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = UIColor.clear
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.register(DeviceCollectionViewCell.self, forCellWithReuseIdentifier: reuseIdentifier)
        return collection
    }()
    
    var backgroundView: UIImageView = {
        let imageView = UIImageView(image: nil)
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    
    let titleLabel: UILabel = {
        let lable = UILabel()
        lable.text = "ArtLight"
        lable.font = UIFont.boldSystemFont(ofSize: 45)
        lable.translatesAutoresizingMaskIntoConstraints = false
        lable.textAlignment = .left
        lable.textColor = UIColor.white
        return lable
    }()
    
    private func addSubViews() {
        //Set imageView in the background.
        self.view.addSubview(backgroundView)
        self.view.addSubview(titleLabel)
        
        collectionView.dataSource = self
        collectionView.delegate = self
        self.view.addSubview(collectionView)
    }
    
    private func setupconstraints() {
        
        titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30).isActive = true
        titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16).isActive = true
        
        backgroundView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        backgroundView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        backgroundView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        
        collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10).isActive = true
        collectionView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        collectionView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    }
    
    var myPhoton : ParticleDevice?
    var devicesSource: [Device] = []
    
    // MARK: Controller logic
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.addSubViews()
        self.setupconstraints()
        self.getBackgroundImage()
        
//        getBackgroundImage()
        getDevices()
//        // Do any additional setup after loading the view, typically from a nib.
//
//        ParticleCloud.sharedInstance().login(withUser: "airllcpr@gmail.com", password: "Stevejobs@4848") { (error:Error?) -> Void in
//            if let _ = error {
//                print("Wrong credentials or no internet connectivity, please try again")
//            }
//            else {
//
//                print("Logged in")
//            }
//        }
    }
    
  
    
    func getDevices()  {
        ParticleCloud.sharedInstance().getDevices { (devices:[ParticleDevice]?, error:Error?) -> Void in
            if let _ = error {
                print("Check your internet connectivity")
            }
            else {
                if let d = devices {
                    for device in d {
                        self.devicesSource.append(Device(particalDevice: device, imageName: "test.png", title: "best Art ever", color: LightColor(red: "0", green: "0", blue: "0", white: "0")))
                        self.collectionView.reloadData()
                    }
                }
            }
        }
    }
    
    func getBackgroundImage() {
        let url = URL(string: "https://source.unsplash.com/featured/?abstract,art")
            URLSession.shared.dataTask(with: url!, completionHandler: { (data, response, error) in
                if error != nil { print(error!); return}
                DispatchQueue.main.async {
                   self.backgroundView.image = UIImage(data: data!)
                }
            }).resume()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

extension ViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        // this will always be 1, for now
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return devicesSource.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as? DeviceCollectionViewCell
        cell?.background.image = UIImage(imageLiteralResourceName: devicesSource[indexPath.row].imageName)
        cell?.titleLabel.text = devicesSource[indexPath.row].title
        return cell!
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
       
        self.performSegue(withIdentifier: "ControllerSegue", sender: nil);
    }
}







