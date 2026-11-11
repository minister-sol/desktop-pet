// AppDelegate.swift
// Manages the collection of pets and the single menubar controller.
// Each pet = one AppSettings instance + one OverlayWindowController.

import AppKit
import Combine

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - State
    private var pets: [OverlayWindowController] = []
    private let petsStore: PetsStore
    private var menuBarController: MenuBarController!
    private var reminderScheduler: ReminderScheduler!
    private var reminderSubscription: AnyCancellable?

    override init() {
        petsStore = PetsStore()
        super.init()
    }

    #if DEBUG
    init(petsStore: PetsStore, scheduler: ReminderScheduler, pets: [OverlayWindowController]) {
        self.petsStore = petsStore
        self.reminderScheduler = scheduler
        self.pets = pets
        super.init()
        connectReminders()
        pets.forEach { observeVisibility(of: $0) }
        redistributeReminders()
    }
    #endif

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        reminderScheduler = ReminderScheduler()
        menuBarController = MenuBarController()
        menuBarController.reminderScheduler = reminderScheduler
        connectReminders()
        menuBarController.onAddPet    = { [weak self] in self?.addPet() }
        menuBarController.onRemovePet = { [weak self] id in self?.removePet(id: id) }

        let savedRecords = petsStore.loadRecords()

        if savedRecords.isEmpty {
            addPet()
        } else {
            for record in savedRecords {
                let settings = makeSettings(record: record)
                let wc = OverlayWindowController(settings: settings)
                observeVisibility(of: wc)

                if let bookmark = settings.assetBookmark {
                    wc.loadAssetFromBookmark(bookmark) { [weak self, wc] success in
                        guard let self, success else { return }
                        wc.showWindow(nil)
                        self.pets.append(wc)
                        self.menuBarController.update(pets: self.pets)
                        self.redistributeReminders()
                    }
                }
            }
            menuBarController.update(pets: pets)
            redistributeReminders()
        }
    }

    private func connectReminders() {
        reminderScheduler.onDelivery = { [weak self] pending in
            guard let self, let pet = self.pets.first(where: { $0.isVisible }) else { return }
            pet.showReminder(pending) { [weak self] id in
                self?.reminderScheduler.dismiss(id) ?? false
            }
        }
        reminderSubscription = reminderScheduler.$data.sink { [weak self] data in
            let ids = Set(data.pending.map(\.id))
            self?.pets.forEach { $0.retainReminders(ids: ids) }
        }
    }

    private func observeVisibility(of pet: OverlayWindowController) {
        pet.onVisibilityChanged = { [weak self] in self?.redistributeReminders() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Add / Remove

    func addPet() {
        let urls = menuBarController.openAddPetsPicker()
        guard !urls.isEmpty else { return }

        for url in urls { addPet(for: url) }
    }

    func removePet(id: String) {
        guard let idx = pets.firstIndex(where: { $0.settings.instanceID == id }) else { return }
        let wc = pets[idx]
        wc.window?.close()
        pets.remove(at: idx)
        redistributeReminders()
        petsStore.remove(instanceID: id)
        menuBarController?.update(pets: pets)
    }

    // MARK: - Helpers

    private func addPet(for url: URL) {
        let record = petsStore.makeNewPetRecord()
        let settings = makeSettings(record: record)
        let wc = OverlayWindowController(settings: settings)
        observeVisibility(of: wc)
        wc.loadAsset(url: url) { [weak self, wc] success in
            guard let self, success else { return }
            wc.showWindow(nil)
            self.pets.append(wc)
            self.petsStore.upsert(settings.toRecord())
            self.menuBarController.update(pets: self.pets)
            self.redistributeReminders()
        }
    }

    private func makeSettings(record: PetRecord) -> AppSettings {
        AppSettings(record: record) { [weak self] settings in
            self?.petsStore.upsert(settings.toRecord())
        }
    }

    private func redistributeReminders() {
        guard let scheduler = reminderScheduler else { return }
        let target = pets.first(where: { $0.isVisible })
        for pet in pets where pet !== target { pet.retainReminders(ids: []) }
        guard let target else { return }
        for pending in scheduler.data.pending {
            target.showReminder(pending) { [weak self] id in
                self?.reminderScheduler.dismiss(id) ?? false
            }
        }
    }
}
