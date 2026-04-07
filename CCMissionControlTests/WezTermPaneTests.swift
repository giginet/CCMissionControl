import Foundation
import Testing

@testable import CCMissionControl

struct WezTermPaneDecodingTests {
    @Test func decodesRealWezTermJSON() throws {
        let json = """
            [
              {
                "window_id": 0,
                "tab_id": 0,
                "pane_id": 0,
                "workspace": "default",
                "size": { "rows": 54, "cols": 106, "pixel_width": 2014, "pixel_height": 2052, "dpi": 144 },
                "title": "⠂ cc-mission-control-impl",
                "cwd": "file:///Users/giginet/work/Swift/CCMissionControl",
                "cursor_x": 2,
                "cursor_y": 47,
                "cursor_shape": "Default",
                "cursor_visibility": "Hidden",
                "left_col": 0,
                "top_row": 0,
                "tab_title": "",
                "window_title": "⠂ cc-mission-control-impl",
                "is_active": true,
                "is_zoomed": false,
                "tty_name": "/dev/ttys000"
              }
            ]
            """
        let panes = try JSONDecoder().decode([WezTermPane].self, from: Data(json.utf8))
        #expect(panes.count == 1)
        #expect(panes[0].paneId == 0)
        #expect(panes[0].workspace == "default")
        #expect(panes[0].title == "⠂ cc-mission-control-impl")
        #expect(panes[0].cwd == "file:///Users/giginet/work/Swift/CCMissionControl")
        #expect(panes[0].ttyName == "/dev/ttys000")
    }

    @Test func decodesMultiplePanes() throws {
        let json = """
            [
              { "pane_id": 0, "tab_id": 0, "workspace": "default", "title": "zsh", "cwd": "file:///tmp", "tty_name": "/dev/ttys000", "is_active": true },
              { "pane_id": 1, "tab_id": 1, "workspace": "work", "title": "vim", "cwd": "file:///home", "tty_name": "/dev/ttys001", "is_active": false }
            ]
            """
        let panes = try JSONDecoder().decode([WezTermPane].self, from: Data(json.utf8))
        #expect(panes.count == 2)
        #expect(panes[1].workspace == "work")
    }
}
