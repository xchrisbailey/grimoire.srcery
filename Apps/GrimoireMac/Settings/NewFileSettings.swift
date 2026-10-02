import GrimoireCore
import SwiftUI

/// Where new files go and what they're called.
struct NewFileSettings: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Section {
            Picker("New files go in", selection: $preferences.newFileLocation) {
                Text("The open file's folder").tag(NewFileLocation.besideSelection)
                Text("The top of the first folder").tag(NewFileLocation.firstFolder)
                Text("A folder of my choosing").tag(NewFileLocation.subfolder)
            }
            if preferences.newFileLocation == .subfolder {
                TextField("Folder", text: $preferences.newFileFolder, prompt: Text("Inbox"))
            }
            TextField("Name new files", text: $preferences.newFileName, prompt: Text(FileNaming.defaultTemplate))
        } header: {
            Text("New files")
        } footer: {
            Text(footer)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: String {
        let example = FileNaming.name(from: preferences.newFileName)
        if preferences.newFileLocation == .subfolder {
            return String(
                localized: """
                    The folder is inside the project's first folder and is made if it's missing. \
                    {date} and {time} fill in, so a new file now is “\(example).md”.
                    """
            )
        }
        return String(localized: "{date} and {time} fill in, so a new file now is “\(example).md”.")
    }
}

/// The sidebar's sort order and whether hidden files show.
struct SidebarListingSettings: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Section("Sidebar") {
            Picker("Sort by", selection: $preferences.fileSort) {
                Text("Name").tag(FileSort.name)
                Text("Date Modified").tag(FileSort.modified)
                Text("Date Created").tag(FileSort.created)
            }
            Toggle("Keep folders on top", isOn: $preferences.foldersFirst)
            Toggle("Show hidden files", isOn: $preferences.showsHiddenFiles)
        }
    }
}
