package com.ladiabla.app

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat

class FloatingBubbleService : Service() {

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var dismissView: View? = null
    private var isViewAdded = false
    private var isDismissViewAdded = false
    private var isOverDismissZone = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startAsForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            removeFloatingBubble()
            removeDismissTarget()
            stopSelf()
            return START_NOT_STICKY
        }

        if (Settings.canDrawOverlays(this)) {
            showFloatingBubble()
        } else {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun startAsForeground() {
        val channelId = "floating_bubble_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Acceso Rápido Flotante",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Mantiene el acceso rápido flotante de La Diabla"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("La Diabla Repartidor")
            .setContentText("Acceso rápido activo sobre otras apps")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()

        startForeground(1001, notification)
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showFloatingBubble() {
        if (isViewAdded || !Settings.canDrawOverlays(this)) return

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val sizeInDp = 64
        val sizeInPx = dpToPx(sizeInDp)

        val params = WindowManager.LayoutParams(
            sizeInPx,
            sizeInPx,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 20
            y = 350
        }

        // Crear la vista circular de la burbuja flotante
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            val shape = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#DC2626"))
                setStroke(4, Color.WHITE)
            }
            background = shape
            elevation = 16f
        }

        val icon = ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher)
            val iconSize = (sizeInPx * 0.65).toInt()
            layoutParams = LinearLayout.LayoutParams(iconSize, iconSize)
        }

        val label = TextView(this).apply {
            text = "Diabla"
            setTextColor(Color.WHITE)
            textSize = 9f
            setTypeface(null, Typeface.BOLD)
            gravity = Gravity.CENTER
        }

        container.addView(icon)
        container.addView(label)

        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isClick = false
        var isDragging = false

        container.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isClick = true
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val diffX = (event.rawX - initialTouchX).toInt()
                    val diffY = (event.rawY - initialTouchY).toInt()
                    if (Math.abs(diffX) > 10 || Math.abs(diffY) > 10) {
                        isClick = false
                        if (!isDragging) {
                            isDragging = true
                            showDismissTarget()
                        }
                    }

                    params.x = initialX + diffX
                    params.y = initialY + diffY
                    try {
                        windowManager?.updateViewLayout(container, params)
                    } catch (_: Exception) {}

                    // Detectar si está sobre la zona inferior de eliminar/cerrar
                    if (isDragging) {
                        val screenHeight = resources.displayMetrics.heightPixels
                        val screenWidth = resources.displayMetrics.widthPixels
                        val inBottomZone = event.rawY > (screenHeight - dpToPx(130))
                        val inCenterZone = Math.abs(event.rawX - (screenWidth / 2f)) < dpToPx(110)
                        val overDismiss = inBottomZone && inCenterZone
                        updateDismissTargetHighlight(overDismiss)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val wasOverDismiss = isOverDismissZone
                    removeDismissTarget()

                    if (wasOverDismiss) {
                        // El usuario arrastró la burbuja a la caneca/X inferior para cerrarla
                        removeFloatingBubble()
                        stopSelf()
                    } else if (isClick) {
                        bringAppToForeground()
                    } else {
                        // Acomodar al borde de pantalla más cercano
                        val screenWidth = resources.displayMetrics.widthPixels
                        val snapX = if (params.x + sizeInPx / 2 < screenWidth / 2) 20 else (screenWidth - sizeInPx - 20)
                        params.x = snapX
                        try {
                            windowManager?.updateViewLayout(container, params)
                        } catch (_: Exception) {}
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    removeDismissTarget()
                    true
                }
                else -> false
            }
        }

        try {
            windowManager?.addView(container, params)
            floatingView = container
            isViewAdded = true
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun showDismissTarget() {
        if (isDismissViewAdded) return
        val wm = windowManager ?: return

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val targetWidth = dpToPx(150)
        val targetHeight = dpToPx(56)

        val params = WindowManager.LayoutParams(
            targetWidth,
            targetHeight,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dpToPx(36)
        }

        val targetContainer = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dpToPx(12), dpToPx(8), dpToPx(12), dpToPx(8))
            val shape = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(28).toFloat()
                setColor(Color.parseColor("#E51F2937")) // Gray 800 translúcido
                setStroke(dpToPx(2), Color.parseColor("#EF4444")) // Borde rojo
            }
            background = shape
            elevation = 24f
        }

        val icon = TextView(this).apply {
            text = "✕"
            setTextColor(Color.parseColor("#EF4444"))
            textSize = 18f
            setTypeface(null, Typeface.BOLD)
            gravity = Gravity.CENTER
        }

        val label = TextView(this).apply {
            text = "  Soltar para cerrar"
            setTextColor(Color.WHITE)
            textSize = 11f
            setTypeface(null, Typeface.BOLD)
            gravity = Gravity.CENTER
        }

        targetContainer.addView(icon)
        targetContainer.addView(label)

        try {
            wm.addView(targetContainer, params)
            dismissView = targetContainer
            isDismissViewAdded = true
            isOverDismissZone = false
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun updateDismissTargetHighlight(isOver: Boolean) {
        if (isOver == isOverDismissZone) return
        isOverDismissZone = isOver

        val target = dismissView as? LinearLayout ?: return
        val bg = target.background as? GradientDrawable ?: return

        if (isOver) {
            bg.setColor(Color.parseColor("#DC2626")) // Rojo intenso al pasar por encima
            bg.setStroke(dpToPx(2), Color.WHITE)
            vibrateFeedback()
        } else {
            bg.setColor(Color.parseColor("#E51F2937"))
            bg.setStroke(dpToPx(2), Color.parseColor("#EF4444"))
        }
    }

    private fun removeDismissTarget() {
        if (isDismissViewAdded && dismissView != null) {
            try {
                windowManager?.removeView(dismissView)
            } catch (e: Exception) {
                e.printStackTrace()
            }
            dismissView = null
            isDismissViewAdded = false
            isOverDismissZone = false
        }
    }

    private fun vibrateFeedback() {
        try {
            val v = getSystemService(Context.VIBRATOR_SERVICE) as? android.os.Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v?.vibrate(android.os.VibrationEffect.createOneShot(35, android.os.VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                v?.vibrate(35)
            }
        } catch (_: Exception) {}
    }

    private fun dpToPx(dp: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    private fun bringAppToForeground() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        if (launchIntent != null) {
            startActivity(launchIntent)
        }
        removeFloatingBubble()
        removeDismissTarget()
        stopSelf()
    }

    private fun removeFloatingBubble() {
        if (isViewAdded && floatingView != null) {
            try {
                windowManager?.removeView(floatingView)
            } catch (e: Exception) {
                e.printStackTrace()
            }
            floatingView = null
            isViewAdded = false
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        removeFloatingBubble()
        removeDismissTarget()
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        removeFloatingBubble()
        removeDismissTarget()
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "ACTION_START_FLOATING_BUBBLE"
        const val ACTION_STOP = "ACTION_STOP_FLOATING_BUBBLE"
    }
}
