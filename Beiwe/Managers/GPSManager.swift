//
//  GPSManager.swift
//  Beiwe
//
//  Created by Keary Griffin on 3/29/16.
//  Copyright © 2016 Rocketfarm Studios. All rights reserved.
//

import Foundation
import CoreLocation
import Darwin


protocol DataServiceProtocol {
    func initCollecting();
    func startCollecting();
    func pauseCollecting();
    func finishCollecting();
}

class DataServiceStatus {
    let onDurationSeconds: Double;
    let offDurationSeconds: Double;
    var currentlyOn: Bool;
    var nextToggleTime: NSDate?;
    let handler: DataServiceProtocol;

    init(onDurationSeconds: Int, offDurationSeconds: Int, handler: DataServiceProtocol) {
        self.onDurationSeconds = Double(onDurationSeconds);
        self.offDurationSeconds = Double(offDurationSeconds);
        self.handler = handler;
        currentlyOn = false;
        nextToggleTime = NSDate();
        // nextToggleTime = NSDate().dateByAddingTimeInterval(self.offDurationSeconds);
    }
}

class GPSManager : NSObject, CLLocationManagerDelegate, DataServiceProtocol {
    let locationManager = CLLocationManager();
    var lastLocations: [CLLocation]?;
    var isCollectingGps: Bool = false;
    var dataCollectionServices: [DataServiceStatus] = [ ];
    var gpsStore: DataStorage?;
    static let headers = [ "timestamp", "latitude", "longitude", "altitude", "accuracy"];

    func startGpsAndTimer() {
        locationManager.delegate = self;
        locationManager.activityType = CLActivityType.Other;
        if #available(iOS 9.0, *) {
            locationManager.allowsBackgroundLocationUpdates = true
        } else {
            // Fallback on earlier versions
        };
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestAlwaysAuthorization();
        locationManager.pausesLocationUpdatesAutomatically = false;
        locationManager.startUpdatingLocation();

    }

    func stopAndClear() {
        locationManager.stopUpdatingLocation();
        for dataStatus in dataCollectionServices {
            dataStatus.handler.finishCollecting();
        }
        dataCollectionServices.removeAll();
    }

    func dispatchToServices() -> NSDate {
        let currentDate = NSDate().timeIntervalSince1970;
        var nextServiceDate = currentDate + (15 * 60);

        for dataStatus in dataCollectionServices {
            if let nextToggleTime = dataStatus.nextToggleTime {
                var serviceDate = nextToggleTime.timeIntervalSince1970;
                if (serviceDate <= currentDate) {
                    if (dataStatus.currentlyOn) {
                        dataStatus.handler.pauseCollecting();
                        dataStatus.currentlyOn = false;
                        dataStatus.nextToggleTime = NSDate(timeIntervalSince1970: currentDate + dataStatus.offDurationSeconds);
                    } else {
                        dataStatus.handler.startCollecting();
                        dataStatus.currentlyOn = true;
                        /* If there is no off time, we run forever... */
                        if (dataStatus.offDurationSeconds == 0) {
                            dataStatus.nextToggleTime = nil;
                        } else {
                            dataStatus.nextToggleTime = NSDate(timeIntervalSince1970: currentDate + dataStatus.onDurationSeconds);
                        }
                    }
                    serviceDate = dataStatus.nextToggleTime?.timeIntervalSince1970 ?? DBL_MAX;
                }
                nextServiceDate = min(nextServiceDate, serviceDate);
            }
        }
        return NSDate(timeIntervalSince1970: nextServiceDate)
    }

    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {

        let nextServiceDate = dispatchToServices();

        if (isCollectingGps) {
            recordGpsData(manager, locations: locations);
        }

        let nextServiceSeconds = min(nextServiceDate.timeIntervalSince1970 - NSDate().timeIntervalSince1970, 1.0);

        if (!isCollectingGps) {
            locationManager.allowDeferredLocationUpdatesUntilTraveled(10000, timeout: nextServiceSeconds);
        }

    }

    func recordGpsData(manager: CLLocationManager, locations: [CLLocation]) {
        //print("Record locations: \(locations)");
        for loc in locations {
            var data: [String] = [];

            //     static let headers = [ "timestamp", "latitude", "longitude", "altitude", "accuracy", "vert_accuracy"];

            data.append(String(Int64(loc.timestamp.timeIntervalSince1970 * 1000)))
            data.append(String(loc.coordinate.latitude))
            data.append(String(loc.coordinate.longitude))
            data.append(String(loc.altitude))
            data.append(String(loc.horizontalAccuracy))
            gpsStore?.store(data);
        }
    }

    func addDataService(on: Int, off: Int, handler: DataServiceProtocol) {
        let dataServiceStatus = DataServiceStatus(onDurationSeconds: on, offDurationSeconds: off, handler: handler);
        dataCollectionServices.append(dataServiceStatus);
        handler.initCollecting();
    }

    func addDataService(handler: DataServiceProtocol) {
        addDataService(1, off: 0, handler: handler);
    }
    /* Data service protocol */

    func initCollecting() {
        gpsStore = DataStorageManager.sharedInstance.createStore("gps", headers: GPSManager.headers);
        isCollectingGps = false;
    }
    func startCollecting() {
        print("Turning GPS collection on");
        isCollectingGps = true;
    }
    func pauseCollecting() {
        print("Pausing GPS collection");
        isCollectingGps = false;
        gpsStore?.flush();
    }
    func finishCollecting() {
        pauseCollecting();
        DataStorageManager.sharedInstance.closeStore("gps");
        gpsStore = nil;
        isCollectingGps = false;
    }
}