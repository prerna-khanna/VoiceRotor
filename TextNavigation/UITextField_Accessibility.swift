//
//  Untitled.swift
//  TextNavigation
//
//  Created by Prerna Khanna on 4/2/25.
//



import UIKit

extension UITextField {
    
    // Clear method to announce only the selected text without extra verbiage
    func announceSelectedTextOnly() {
        guard let selectedRange = self.selectedTextRange else { return }
        
        if let selectedText = self.text(in: selectedRange), !selectedText.isEmpty {
            // Directly announce just the selected text
            // This bypasses VoiceOver's default behavior that might add "selected" or other phrases
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                UIAccessibility.post(notification: .announcement, argument: selectedText)
            }
        } else {
            // If nothing is selected, announce an empty space character
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                UIAccessibility.post(notification: .announcement, argument: " ")
            }
        }
    }
}
