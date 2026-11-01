package tech.northstarlabs.fitquest

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorManager
import android.os.Build
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private val prefs get() = getSharedPreferences("fitquest_steps", MODE_PRIVATE)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fitquest/steps")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        val sensor = (getSystemService(SENSOR_SERVICE) as SensorManager).getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
                        if (sensor == null) {
                            result.error("unavailable", "This phone has no step counter sensor.", null)
                        } else if (Build.VERSION.SDK_INT >= 29 && checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED) {
                            if (permissionResult != null) result.error("pending", "Permission request already open.", null)
                            else { permissionResult = result; requestPermissions(arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), 7101) }
                        } else {
                            try { enableSteps(true); result.success(null) }
                            catch (e: Exception) { result.error("start", "Could not start step counting. Please try again.", null) }
                        }
                    }
                    "disable" -> {
                        prefs.edit().putBoolean("enabled", false).remove("raw").apply()
                        stopService(Intent(this, StepService::class.java))
                        result.success(null)
                    }
                    "read" -> {
                        val permitted = Build.VERSION.SDK_INT < 29 || checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
                        val enabled = permitted && prefs.getBoolean("enabled", false)
                        if (enabled) {
                            try { enableSteps() } catch (_: Exception) { }
                        }
                        val date = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
                        result.success(mapOf("steps" to prefs.getInt("day_$date", 0), "enabled" to enabled,
                            "status" to if (enabled) "Phone sensor active · pause in Account & sync" else "Enable motion permission to count steps"))
                    }
                    else -> result.notImplemented()
                }
            }
    }
    private fun enableSteps(requestNotifications: Boolean = false) {
        prefs.edit().putBoolean("enabled", true).apply()
        val intent = Intent(this, StepService::class.java)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
        if (requestNotifications && Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7103)
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7101) {
            val result = permissionResult
            permissionResult = null
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                try { enableSteps(true); result?.success(null) }
                catch (_: Exception) { result?.error("start", "Could not start background step counting.", null) }
            } else result?.error("permission", "Motion permission is needed. You can enable it in phone settings.", null)
        }
    }
}
