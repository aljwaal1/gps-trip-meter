package com.explapp.gpstripmeterlegacy;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.Locale;

public class MainActivity extends Activity implements LocationListener {
    private static final int REQ_LOCATION = 10;
    private static final String PREFS = "legacy_trip";
    private static final String KEY_DISTANCE = "distance";
    private static final String KEY_SECONDS = "seconds";
    private static final String KEY_MAX_SPEED = "max_speed";
    private static final String KEY_RUNNING = "running";

    private TextView distanceView, timeView, maxSpeedView, statusView, startButton;
    private SpeedGauge speedGauge;
    private LocationManager locationManager;
    private Location lastLocation;
    private float totalMeters, maxSpeedKmh, currentSpeedKmh;
    private long trackedSeconds, startedAt;
    private long lastSavedSecond;
    private boolean tracking;
    private final Handler dashboardHandler = new Handler();
    private final Runnable dashboardTick = new Runnable() {
        @Override public void run() {
            if (tracking && startedAt > 0) { addElapsed(); refreshDashboard(); saveSessionThrottled(); }
            dashboardHandler.postDelayed(this, 1000L);
        }
    };

    @Override public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        loadSession();
        buildScreen();
        refreshDashboard();
        dashboardHandler.post(dashboardTick);
        if (tracking) startTracking();
    }

    private void buildScreen() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(12), dp(12), dp(12), dp(12));
        if (android.os.Build.VERSION.SDK_INT >= 17) root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        GradientDrawable background = new GradientDrawable(GradientDrawable.Orientation.TL_BR,
                new int[]{Color.rgb(7, 17, 31), Color.rgb(15, 45, 66)});
        root.setBackground(background);

        TextView title = text("عداد الرحلة", 28, Color.WHITE, true);
        title.setGravity(Gravity.CENTER);
        root.addView(title, match());
        TextView subtitle = text("GPS • سريع وخفيف لأجهزة Android 4.4", 14, Color.rgb(167, 205, 235), false);
        subtitle.setGravity(Gravity.CENTER);
        subtitle.setPadding(0, dp(4), 0, dp(16));
        root.addView(subtitle, match());

        speedGauge = new SpeedGauge(this);
        int heightDp = (int) (getResources().getDisplayMetrics().heightPixels / getResources().getDisplayMetrics().density);
        root.addView(speedGauge, new LinearLayout.LayoutParams(-1, dp(heightDp < 560 ? 190 : 220)));

        LinearLayout stats = new LinearLayout(this);
        stats.setOrientation(LinearLayout.HORIZONTAL);
        stats.setPadding(0, dp(12), 0, dp(8));
        distanceView = statCard("المسافة", "0.00 كم");
        timeView = statCard("المدة", "00:00");
        maxSpeedView = statCard("أعلى سرعة", "0 كم/س");
        stats.addView(distanceView, weight()); stats.addView(space(8), fixed(8));
        stats.addView(timeView, weight()); stats.addView(space(8), fixed(8)); stats.addView(maxSpeedView, weight());
        root.addView(stats, match());

        statusView = text("بانتظار بدء الرحلة", 15, Color.rgb(226, 239, 249), false);
        statusView.setGravity(Gravity.CENTER);
        statusView.setPadding(dp(10), dp(12), dp(10), dp(12));
        statusView.setBackground(round(Color.rgb(33, 60, 82), 14));
        root.addView(statusView, match());

        startButton = button("بدء الرحلة", Color.rgb(27, 174, 128));
        startButton.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { toggleTracking(); } });
        root.addView(startButton, matchWithTop(14));
        LinearLayout secondary = new LinearLayout(this);
        secondary.setOrientation(LinearLayout.HORIZONTAL);
        secondary.setPadding(0, dp(8), 0, 0);
        Button reset = button("تصفير", Color.rgb(67, 91, 112));
        reset.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { confirmReset(); } });
        secondary.addView(reset, weight());
        secondary.addView(space(8), fixed(8));
        Button settings = button("إعدادات GPS", Color.rgb(54, 91, 125));
        settings.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { try { startActivity(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)); } catch (Exception ignored) { statusView.setText("تعذر فتح إعدادات الموقع على هذا الجهاز"); } } });
        secondary.addView(settings, weight());
        root.addView(secondary, match());

        TextView footer = text("تُحفظ الرحلة تلقائيًا، ويتوقف GPS عند مغادرة التطبيق لتوفير البطارية.", 12, Color.rgb(141, 175, 199), false);
        footer.setGravity(Gravity.CENTER); footer.setPadding(0, dp(12), 0, 0); root.addView(footer, match());
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true); scroll.setBackgroundColor(Color.rgb(7, 17, 31)); scroll.addView(root); setContentView(scroll);
        locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
    }

    private void toggleTracking() { if (tracking) pauseTracking(); else beginTracking(); }

    private void beginTracking() {
        if (!hasLocationPermission()) { tracking = false; startedAt = 0; requestLocationPermission(); return; }
        tracking = true; lastLocation = null; currentSpeedKmh = 0f;
        startedAt = SystemClock.elapsedRealtime();
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        startTracking(); refreshDashboard(); saveSession();
    }

    @SuppressLint("MissingPermission")
    private void startTracking() {
        if (!hasLocationPermission()) { requestLocationPermission(); return; }
        if (startedAt <= 0) startedAt = SystemClock.elapsedRealtime();
        try {
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 1f, this);
            locationManager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 3000L, 5f, this);
            statusView.setText("جاري تسجيل الرحلة… ابقَ في مكان مكشوف لتحسين GPS");
        } catch (Exception error) { statusView.setText("تعذر تشغيل GPS. تحقق من إعدادات الموقع."); }
    }

    private void pauseTracking() {
        addElapsed(); tracking = false; startedAt = 0; lastLocation = null; currentSpeedKmh = 0f;
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (locationManager != null) try { locationManager.removeUpdates(this); } catch (Exception ignored) { }
        statusView.setText("الرحلة متوقفة مؤقتًا — يمكنك المتابعة لاحقًا"); refreshDashboard(); saveSession();
    }

    private boolean hasLocationPermission() {
        return android.os.Build.VERSION.SDK_INT < 23 || checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    private void requestLocationPermission() {
        if (android.os.Build.VERSION.SDK_INT >= 23) requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION}, REQ_LOCATION);
        else { statusView.setText("صلاحية الموقع مطلوبة لتسجيل الرحلة"); tracking = false; }
    }

    @Override public void onLocationChanged(Location location) {
        if (!tracking || startedAt <= 0) return;
        addElapsed();
        if (location.hasAccuracy() && location.getAccuracy() > 35f) { statusView.setText("إشارة ضعيفة: دقة " + Math.round(location.getAccuracy()) + " م"); refreshDashboard(); return; }
        if (location.getTime() > 0 && System.currentTimeMillis() - location.getTime() > 15000L) return;
        float speed = location.hasSpeed() ? location.getSpeed() * 3.6f : 0f;
        if (speed > 240f) { statusView.setText("تم تجاهل قراءة سرعة غير واقعية"); return; }
        if (lastLocation != null) {
            float delta = lastLocation.distanceTo(location);
            long gap = location.getTime() - lastLocation.getTime();
            if (gap <= 0) return;
            float seconds = gap / 1000f;
            float noiseFloor = Math.max(2.5f, Math.max(location.getAccuracy(), lastLocation.getAccuracy()) * .25f);
            float plausibleLimit = 20f + seconds * 75f;
            boolean accepted = gap <= 30000L && delta >= noiseFloor && delta <= plausibleLimit;
            if (accepted) {
                totalMeters += delta;
                if (!location.hasSpeed()) speed = delta / seconds * 3.6f;
            } else if (!location.hasSpeed()) speed = 0f;
        }
        currentSpeedKmh = Math.max(0f, Math.min(240f, speed));
        if (currentSpeedKmh > maxSpeedKmh) maxSpeedKmh = currentSpeedKmh;
        lastLocation = location;
        String source = LocationManager.GPS_PROVIDER.equals(location.getProvider()) ? "GPS" : "الشبكة";
        statusView.setText(source + " متصل • الدقة " + Math.round(location.getAccuracy()) + " م");
        refreshDashboard(); saveSessionThrottled();
    }

    private void addElapsed() { if (tracking && startedAt > 0) { long wholeSeconds = Math.max(0, (SystemClock.elapsedRealtime() - startedAt) / 1000L); if (wholeSeconds > 0) { trackedSeconds += wholeSeconds; startedAt += wholeSeconds * 1000L; } } }
    private void resetTrip() {
        if (tracking) pauseTracking(); totalMeters = 0f; maxSpeedKmh = 0f; trackedSeconds = 0; lastLocation = null;
        statusView.setText("تم تصفير الرحلة. اضغط بدء الرحلة للتسجيل."); refreshDashboard(); saveSession();
    }

    private void confirmReset() {
        new AlertDialog.Builder(this)
                .setTitle("تصفير الرحلة؟")
                .setMessage("سيتم حذف المسافة والمدة وأعلى سرعة الحالية.")
                .setNegativeButton("إلغاء", null)
                .setPositiveButton("تصفير", new DialogInterface.OnClickListener() {
                    @Override public void onClick(DialogInterface dialog, int which) { resetTrip(); }
                }).show();
    }

    private void refreshDashboard() {
        speedGauge.setSpeed(tracking ? currentSpeedKmh : 0f);
        distanceView.setText("المسافة\n" + String.format(Locale.US, "%.2f كم", totalMeters / 1000f));
        timeView.setText("المدة\n" + formatDuration(trackedSeconds));
        maxSpeedView.setText("الأعلى\n" + String.format(Locale.US, "%.0f كم/س", maxSpeedKmh));
        startButton.setText(tracking ? "إيقاف مؤقت" : (totalMeters > 0 ? "متابعة الرحلة" : "بدء الرحلة"));
        startButton.setBackground(round(tracking ? Color.rgb(221, 103, 68) : Color.rgb(27, 174, 128), 16));
    }

    private String formatDuration(long seconds) { return String.format(Locale.US, "%02d:%02d", seconds / 60L, seconds % 60L); }
    private void loadSession() { SharedPreferences p = getSharedPreferences(PREFS, MODE_PRIVATE); totalMeters = p.getFloat(KEY_DISTANCE, 0f); trackedSeconds = p.getLong(KEY_SECONDS, 0L); maxSpeedKmh = p.getFloat(KEY_MAX_SPEED, 0f); lastSavedSecond = trackedSeconds; tracking = false; }
    private void saveSessionThrottled() { if (trackedSeconds - lastSavedSecond >= 10L) saveSession(); }
    private void saveSession() { lastSavedSecond = trackedSeconds; getSharedPreferences(PREFS, MODE_PRIVATE).edit().putFloat(KEY_DISTANCE, totalMeters).putLong(KEY_SECONDS, trackedSeconds).putFloat(KEY_MAX_SPEED, maxSpeedKmh).putBoolean(KEY_RUNNING, false).apply(); }

    @Override public void onProviderEnabled(String provider) { statusView.setText("تم تفعيل " + provider); }
    @Override public void onProviderDisabled(String provider) { if (LocationManager.GPS_PROVIDER.equals(provider)) statusView.setText("GPS مغلق؛ قد تكون قراءة الشبكة أقل دقة"); }
    @Override public void onStatusChanged(String provider, int status, Bundle extras) { }
    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) { super.onRequestPermissionsResult(requestCode, permissions, results); if (requestCode == REQ_LOCATION && results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) { tracking = true; startedAt = SystemClock.elapsedRealtime(); getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); startTracking(); refreshDashboard(); saveSession(); } else if (requestCode == REQ_LOCATION) { tracking = false; startedAt = 0; statusView.setText("صلاحية الموقع مطلوبة لتسجيل الرحلة"); refreshDashboard(); } }
    @Override protected void onResume() { super.onResume(); dashboardHandler.removeCallbacks(dashboardTick); dashboardHandler.post(dashboardTick); if (tracking) { startedAt = SystemClock.elapsedRealtime(); getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); startTracking(); statusView.setText("تم استئناف تسجيل الرحلة"); } }
    @Override protected void onPause() { dashboardHandler.removeCallbacks(dashboardTick); if (tracking) { addElapsed(); startedAt = 0; lastLocation = null; currentSpeedKmh = 0f; saveSession(); if (locationManager != null) try { locationManager.removeUpdates(this); } catch (Exception ignored) { } getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); } super.onPause(); }
    @Override protected void onDestroy() { dashboardHandler.removeCallbacksAndMessages(null); if (locationManager != null) try { locationManager.removeUpdates(this); } catch (Exception ignored) { } super.onDestroy(); }

    private LinearLayout card() { LinearLayout c = new LinearLayout(this); c.setPadding(dp(14), dp(14), dp(14), dp(14)); c.setBackground(round(Color.rgb(27, 49, 67), 22)); return c; }
    private TextView statCard(String label, String value) { TextView v = text(label + "\n" + value, 15, Color.WHITE, true); v.setGravity(Gravity.CENTER); v.setPadding(dp(4), dp(15), dp(4), dp(15)); v.setBackground(round(Color.rgb(30, 57, 78), 16)); return v; }
    private TextView text(String value, int size, int color, boolean bold) { TextView t = new TextView(this); t.setText(value); t.setTextSize(size); t.setTextColor(color); t.setTypeface(Typeface.DEFAULT, bold ? Typeface.BOLD : Typeface.NORMAL); return t; }
    private Button button(String label, int color) { Button b = new Button(this); b.setText(label); b.setTextColor(Color.WHITE); b.setTextSize(17); b.setAllCaps(false); b.setTypeface(Typeface.DEFAULT, Typeface.BOLD); b.setMinHeight(dp(52)); b.setBackground(round(color, 16)); return b; }
    private GradientDrawable round(int color, int radius) { GradientDrawable d = new GradientDrawable(); d.setColor(color); d.setCornerRadius(dp(radius)); return d; }
    private int dp(int value) { return (int) (value * getResources().getDisplayMetrics().density + 0.5f); }
    private View space(int width) { View v = new View(this); v.setLayoutParams(fixed(width)); return v; }
    private LinearLayout.LayoutParams match() { return new LinearLayout.LayoutParams(-1, -2); }
    private LinearLayout.LayoutParams matchWithTop(int top) { LinearLayout.LayoutParams p = match(); p.topMargin = dp(top); return p; }
    private LinearLayout.LayoutParams fixed(int width) { return new LinearLayout.LayoutParams(dp(width), 1); }
    private LinearLayout.LayoutParams weight() { return new LinearLayout.LayoutParams(0, -2, 1f); }

    private static class SpeedGauge extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF arc = new RectF();
        private float speed;

        SpeedGauge(Context context) { super(context); setLayerType(View.LAYER_TYPE_SOFTWARE, null); }
        void setSpeed(float value) { speed = Math.max(0f, Math.min(200f, value)); invalidate(); }

        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float w = getWidth(), h = getHeight();
            float cx = w / 2f, cy = h * .57f, radius = Math.min(w * .34f, h * .43f);
            arc.set(cx - radius, cy - radius, cx + radius, cy + radius);

            paint.setStyle(Paint.Style.STROKE); paint.setStrokeCap(Paint.Cap.ROUND); paint.setStrokeWidth(radius * .12f);
            paint.setColor(Color.rgb(34, 62, 82)); canvas.drawArc(arc, 145, 250, false, paint);
            paint.setColor(Color.rgb(34, 211, 238)); paint.setShadowLayer(14f, 0, 0, Color.rgb(14, 165, 233));
            canvas.drawArc(arc, 145, 250f * speed / 200f, false, paint); paint.clearShadowLayer();

            paint.setStyle(Paint.Style.FILL); paint.setTextAlign(Paint.Align.CENTER); paint.setTypeface(Typeface.DEFAULT_BOLD);
            paint.setColor(Color.rgb(186, 230, 253)); paint.setTextSize(radius * .16f);
            canvas.drawText("السرعة الحالية", cx, cy - radius * .28f, paint);
            paint.setColor(Color.WHITE); paint.setTextSize(radius * .52f);
            canvas.drawText(String.format(Locale.US, "%.0f", speed), cx, cy + radius * .18f, paint);
            paint.setColor(Color.rgb(94, 234, 212)); paint.setTextSize(radius * .15f);
            canvas.drawText("كم / ساعة", cx, cy + radius * .48f, paint);

            paint.setTextSize(radius * .12f); paint.setColor(Color.rgb(148, 180, 202));
            canvas.drawText("0", cx - radius * .88f, cy + radius * .69f, paint);
            canvas.drawText("200", cx + radius * .88f, cy + radius * .69f, paint);
        }
    }
}
