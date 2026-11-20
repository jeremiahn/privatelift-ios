//
//  PrivateLiftWidgetBundle.swift
//  PrivateLiftWidget
//
//  Created by Jeremiah Nelson on 6/14/26.
//

import WidgetKit
import SwiftUI

@main
struct PrivateLiftWidgetBundle: WidgetBundle {
    var body: some Widget {
        // The Xcode template widget ("My Widget") and control ("Start Timer") were removed:
        // they shipped placeholder UI and did nothing. Only the rest-timer Live Activity remains.
        PrivateLiftWidgetLiveActivity()
    }
}
