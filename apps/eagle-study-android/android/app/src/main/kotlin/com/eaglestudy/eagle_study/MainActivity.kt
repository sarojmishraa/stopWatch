package com.eaglestudy.eagle_study

import android.content.Intent
import android.os.Bundle
import com.eaglestudy.eagle_study.alarm.AlarmChannel
import com.eaglestudy.eagle_study.eagle.EagleView
import com.eaglestudy.eagle_study.eagle.EagleViewFactory
import com.eaglestudy.eagle_study.study.StudyModeChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var alarms: AlarmChannel? = null
    private var studyMode: StudyModeChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        captureStudyAction(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureStudyAction(intent)
        StudyModeChannel.pendingAction?.let {
            if (StudyModeChannel.deliver(it)) StudyModeChannel.pendingAction = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        alarms = AlarmChannel(this, messenger)
        studyMode = StudyModeChannel(this, messenger)
        flutterEngine.platformViewsController.registry
            .registerViewFactory(EagleView.VIEW_TYPE, EagleViewFactory(messenger))
        MethodChannel(messenger, "eagle_study/eagle").setMethodCallHandler { call, result ->
            if (call.method == "isSupported") result.success(EagleView.isSupported(this)) else result.notImplemented()
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        alarms?.dispose()
        alarms = null
        studyMode?.dispose()
        studyMode = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** "Finish" on the session notification opens the app with this extra. */
    private fun captureStudyAction(intent: Intent?) {
        intent?.getStringExtra(EXTRA_STUDY_ACTION)?.let {
            StudyModeChannel.pendingAction = it
            intent.removeExtra(EXTRA_STUDY_ACTION)
        }
    }

    companion object {
        const val EXTRA_STUDY_ACTION = "study_action"
    }
}
