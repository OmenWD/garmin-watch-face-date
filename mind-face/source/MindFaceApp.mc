import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class MindFaceApp extends Application.AppBase {

    private var _view as MindFaceView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
        _view = null;
    }

    function getInitialView() {
        _view = new MindFaceView();
        return [ _view ];
    }

    // Fired when settings are edited in Garmin Connect.
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.loadSettings();
        }
        WatchUi.requestUpdate();
    }
}
