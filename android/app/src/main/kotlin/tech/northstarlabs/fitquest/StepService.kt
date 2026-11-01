package tech.northstarlabs.fitquest

import android.app.Service
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.provider.Settings
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class StepService : Service(), SensorEventListener {
    private lateinit var sensors: SensorManager
    private val prefs get() = getSharedPreferences("fitquest_steps", MODE_PRIVATE)
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel("fitquest_steps", "Step counting", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "fitquest_steps") else Notification.Builder(this)
        startForeground(7102, builder.setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("FitQuest step counter")
            .setContentText("Counting steps on this phone. Pause in Account & sync.")
            .setContentIntent(open).setOngoing(true).build())
        sensors = getSystemService(SENSOR_SERVICE) as SensorManager
        val sensor = sensors.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (sensor == null || !sensors.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)) {
            prefs.edit().putBoolean("enabled", false).apply()
            stopSelf()
        }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) { }
    override fun onSensorChanged(event: SensorEvent) {
        val raw = event.values[0].toInt()
        val lastRaw = prefs.getInt("raw", -1)
        val uptime = SystemClock.elapsedRealtime()
        val lastUptime = prefs.getLong("uptime", 0)
        val boot = Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT, 0)
        val sameBoot = prefs.getInt("boot", -1) == boot && uptime >= lastUptime && raw >= lastRaw
        val delta = if (lastRaw >= 0 && sameBoot) raw - lastRaw else 0
        val date = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val total = prefs.getInt("day_$date", 0) + delta
        prefs.edit().putInt("raw", raw).putInt("boot", boot).putLong("uptime", uptime).putInt("day_$date", total).apply()
    }
    override fun onDestroy() {
        if (::sensors.isInitialized) sensors.unregisterListener(this)
        super.onDestroy()
    }
}
