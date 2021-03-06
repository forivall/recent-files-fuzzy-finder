path = require 'path'
_ = require 'underscore-plus'
fs = require 'fs-plus'
temp = require 'temp'
wrench = require 'wrench'
shell = require 'shell'

describe "RecentFilesFuzzyFinder", ->
  [rootDir1, rootDir2] = []
  [recentFilesView, workspaceElement] = []

  beforeEach ->
    rootDir1 = fs.realpathSync(temp.mkdirSync('root-dir1'))
    rootDir2 = fs.realpathSync(temp.mkdirSync('root-dir2'))

    fixturesPath = atom.project.getPaths()[0]

    wrench.copyDirSyncRecursive(
      path.join(fixturesPath, "root-dir1"),
      rootDir1,
      forceDelete: true
    )

    wrench.copyDirSyncRecursive(
      path.join(fixturesPath, "root-dir2"),
      rootDir2,
      forceDelete: true
    )

    atom.project.setPaths([rootDir1, rootDir2])

    workspaceElement = atom.views.getView(atom.workspace)

    waitsForPromise ->
      atom.workspace.open(path.join(rootDir1, 'sample.js'))

    waitsForPromise ->
      atom.packages.activatePackage('recent-files-fuzzy-finder').then (pack) ->
        recentFilesFuzzyFinder = pack.mainModule
        recentFilesView = recentFilesFuzzyFinder.createRecentFilesView()

  dispatchCommand = (command) ->
    atom.commands.dispatch(workspaceElement, "recent-files-fuzzy-finder:#{command}")

  describe 'recent-files finder behaviour', ->
    describe "toggling", ->
      describe "when there are pane items with paths", ->
        beforeEach ->
          jasmine.attachToDOM(workspaceElement)

          waitsForPromise ->
            atom.workspace.open 'sample.txt'

        describe 'serialize/deserialize', ->
          [pack] = []

          beforeEach ->
            paneItem.destroy() for paneItem in atom.workspace.getPaneItems()
            atom.packages.deactivatePackage('recent-files-fuzzy-finder')

          it "restores data when cfg restore last session is set", ->
            waitsForPromise ->
              atom.config.set('recent-files-fuzzy-finder.restoreSession', true)
              atom.packages.activatePackage('recent-files-fuzzy-finder').then (p) ->
                pack = p
            runs ->
              restoredPaths = pack.mainModule.recentFiles.pathsSortedByLastUsage()
              expect(restoredPaths.length).toEqual 2
              expect(restoredPaths[0]).toContain 'sample.txt'
              expect(restoredPaths[1]).toContain 'sample.js'

          it "doesn't restore data by default", ->
            waitsForPromise ->
              atom.packages.activatePackage('recent-files-fuzzy-finder').then (p) ->
                pack = p
            runs ->
              restoredPaths = pack.mainModule.recentFiles.pathsSortedByLastUsage()
              expect(restoredPaths).toEqual []

        it "shows the FuzzyFinder if it isn't showing, or hides it and returns focus to the active editor", ->
          expect(atom.workspace.panelForItem(recentFilesView)).toBeNull()
          atom.workspace.getActivePane().splitRight(copyActiveItem: true)
          [editor1, editor2, editor3] = atom.workspace.getTextEditors()
          expect(atom.workspace.getActivePaneItem()).toBe editor3

          expect(atom.views.getView(editor3)).toHaveFocus()

          dispatchCommand('toggle-finder')
          expect(atom.workspace.panelForItem(recentFilesView).isVisible()).toBe true
          expect(workspaceElement.querySelector('.fuzzy-finder')).toHaveFocus()
          recentFilesView.filterEditorView.getModel().insertText('this should not show up next time we toggle')

          dispatchCommand('toggle-finder')
          expect(atom.views.getView(editor3)).toHaveFocus()
          expect(atom.workspace.panelForItem(recentFilesView).isVisible()).toBe false

          dispatchCommand('toggle-finder')
          expect(recentFilesView.filterEditorView.getText()).toBe ''

        it "lists the paths of recently opened files, sorted by most recent usage but without currently active file", ->
          waitsForPromise ->
            atom.workspace.open 'sample-with-tabs.coffee'

          runs ->
            dispatchCommand('toggle-finder')
            expect(atom.workspace.panelForItem(recentFilesView).isVisible()).toBe true
            expect(_.pluck(recentFilesView.list.find('li > div.file'), 'outerText')).toEqual ['sample.txt', 'sample.js']
            dispatchCommand('toggle-finder')
            expect(atom.workspace.panelForItem(recentFilesView).isVisible()).toBe false

          waitsForPromise ->
            atom.workspace.open 'sample.txt'

          runs ->
            dispatchCommand('toggle-finder')
            expect(atom.workspace.panelForItem(recentFilesView).isVisible()).toBe true
            expect(_.pluck(recentFilesView.list.find('li > div.file'), 'outerText')).toEqual ['sample-with-tabs.coffee', 'sample.js']
            expect(recentFilesView.list.children().first()).toHaveClass 'selected'

            paneItem.destroy() for paneItem in atom.workspace.getPaneItems()
            expect(_.pluck(recentFilesView.list.find('li > div.file'), 'outerText')).toEqual ['sample-with-tabs.coffee', 'sample.js']

        it "ignores anonymous files", ->
          waitsForPromise ->
            atom.workspace.open('unsaved-file')

          runs ->
            dispatchCommand('toggle-finder')
            expect(atom.workspace.panelForItem(recentFilesView).isVisible()).toBe true
            expect(_.pluck(recentFilesView.list.find('li > div.file'), 'outerText')).not.toContain ['unsaved-file']

  describe "call remove closed files", ->
    describe "when there are pane items with paths", ->
      beforeEach ->
        jasmine.attachToDOM(workspaceElement)

        waitsForPromise ->
          atom.workspace.open 'sample.txt'
        waitsForPromise ->
          atom.workspace.open 'sample-with-tabs.coffee'

      it "removes closed files", ->
        paneItem.destroy() for paneItem in atom.workspace.getPaneItems()
        dispatchCommand('toggle-finder')
        expect(atom.workspace.panelForItem(recentFilesView).isVisible()).toBe true
        expect(_.pluck(recentFilesView.list.find('li > div.file'), 'outerText')).toEqual ['sample-with-tabs.coffee', 'sample.txt', 'sample.js']
        dispatchCommand('toggle-finder')

        dispatchCommand('remove-closed-files')
        dispatchCommand('toggle-finder')
        expect(atom.workspace.panelForItem(recentFilesView).isVisible()).toBe false

        waitsForPromise ->
          atom.workspace.open 'sample.js'
        waitsForPromise ->
          atom.workspace.open('new-file')

        runs ->
          dispatchCommand('toggle-finder')
          expect(atom.workspace.panelForItem(recentFilesView).isVisible()).toBe true
          expect(_.pluck(recentFilesView.list.find('li > div.file'), 'outerText')).toEqual ['sample.js']

  describe 'delete a file', ->
    beforeEach ->
      jasmine.attachToDOM(workspaceElement)

      waitsForPromise ->
        atom.workspace.open 'sample.txt'
      waitsForPromise ->
        atom.workspace.open 'sample-with-tabs.coffee'

    it 'does not show the deleted file anymore', ->
      shell.moveItemToTrash path.join(rootDir1, 'sample.txt')

      waitsFor "file to be deleted", 300, ->
        dispatchCommand('toggle-finder')
        _.pluck(recentFilesView.list.find('li > div.file'), 'outerText').length == 1

      runs ->
        expect(_.pluck(recentFilesView.list.find('li > div.file'), 'outerText')).toEqual ['sample.js']

  describe 'when a non-existing path is added', ->
    beforeEach ->
      spyOn(console, 'warn')
      atom.project.setPaths([rootDir1, rootDir2, 'this/do/not/exist'])

    it 'do not watch that directory', ->
      expect(console.warn).toHaveBeenCalled()
      expect(console.warn.calls[0].args[0]).toMatch 'Could not observe path'
      expect(console.warn.calls[0].args[0]).toMatch 'this/do/not/exist'
