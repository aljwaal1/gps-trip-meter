package com.explapp.gpstripmeterlegacy;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.Locale;

public class MainActivity extends Activity implements LocationListener {
    private static final int REQ_LOCATION = 10;
    private static final String PREFS = "legacy_trip";
    private static final String KEY_DISTANCE = "distance";
    private static final String KEY_SECONDS = "seconds";
    private static final String KEY_MAX_SPEED = "max_speed";
    private static final String KEY_RUNNING = "running";

    private TextView speedView, distanceView, timeView, maxSpeedView, statusView, startButton;
    private LocationManager locationManager;
    private Location lastLocation;
    private float totalMeters, maxSpeedKmh;
    private long trackedSeconds, startedAt;
    private boolean tracking;

    @Override public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        loadSession();
        buildScreen();
        refreshDashboard();
        if (tracking) startTracking();
    }

    private void buildScreen() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(18), dp(16), dp(16));
        root.setBackgroundColor(Color.rgb(15, 28, 42));

        TextView title = text("عداد الرحلة", 28, Color.WHITE, true);
        title.setGravity(Gravity.CENTER);
        root.addView(title, match());
        TextView subtitle = text("GPS • سريع وخفيف لأجهزة Android 4.4", 14, Color.rgb(167, 205, 235), false);
        subtitle.setGravity(Gravity.CENTER);
        subtitle.setPadding(0, dp(4), 0, dp(16));
        root.addView(subtitle, match());

        LinearLayout speedCard = card();
        speedCard.setGravity(Gravity.CENTER);
        speedCard.setOrientation(LinearLayout.VERTICAL);
        TextView speedLabel = text("السرعة الحالية", 14, Color.rgb(182, 213, 236), false);
        speedLabel.setGravity(Gravity.CENTER);
        speedView = text("0", 58, Color.WHITE, true);
        speedView.setGravity(Gravity.CENTER);
        TextView unit = text("كم / ساعة", 14, Color.rgb(113, 220, 193), true);
        unit.setGravity(Gravity.CENTER);
        speedCard.addView(speedLabel, match()); speedCard.addView(speedView, match()); speedCard.addView(unit, match());
        root.addView(speedCard, match());

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
        Button reset = button("تصفير الرحلة", Color.rgb(67, 91, 112));
        reset.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { resetTrip(); } });
        root.addView(reset, matchWithTop(8));
        Button settings = button("إعدادات الموقع", Color.rgb(54, 91, 125));
        settings.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { startActivity(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)); } });
        root.addView(settings, matchWithTop(8));

        TextView footer = text("يتم حفظ الرحلة الحالية تلقائيًا على هذا الجهاز.", 12, Color.rgb(141, 175, 199), false);
        footer.setGravity(Gravity.CENTER); footer.setPadding(0, dp(12), 0, 0); root.addView(footer, match());
        setContentView(root);
        locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
    }

    private void toggleTracking() { if (tracking) pauseTracking(); else beginTracking(); }

    private void beginTracking() {
        tracking = true; startedAt = System.currentTimeMillis(); lastLocation = null;
        if (!hasLocationPermission()) { requestLocationPermission(); return; }
        startTracking(); refreshDashboard(); saveSession();
    }

    private void startTracking() {
        if (!hasLocationPermission()) { requestLocationPermission(); return; }
        try {
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 1f, this);
            locationManager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 3000L, 5f, this);
            statusView.setText("جاري تسجيل الرحلة… ابقَ في مكان مكشوف لتحسين GPS");
        } catch (Exception error) { statusView.setText("تعذر تشغيل GPS. تحقق من إعدادات الموقع."); }
    }

    private void pauseTracking() {
        addElapsed(); tracking = false; lastLocation = null;
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
        if (!tracking) return;
        addElapsed();
        if (location.hasAccuracy() && location.getAccuracy() > 60f) { statusView.setText("إشارة ضعيفة: دقة " + Math.round(location.getAccuracy()) + " م"); refreshDashboard(); return; }
        float speed = location.hasSpeed() ? location.getSpeed() * 3.6f : 0f;
        if (speed > maxSpeedKmh) maxSpeedKmh = speed;
        if (lastLocation != null) {
            float delta = lastLocation.distanceTo(location);
            if (delta >= 1f && delta < 180f) totalMeters += delta;
        }
        lastLocation = location;
        statusView.setText("GPS متصل • الدقة " + Math.round(location.getAccuracy()) + " م");
        refreshDashboard(); saveSession();
    }

    private void addElapsed() { if (tracking && startedAt > 0) { long wholeSeconds = Math.max(0, (System.currentTimeMillis() - startedAt) / 1000L); if (wholeSeconds > 0) { trackedSeconds += wholeSeconds; startedAt += wholeSeconds * 1000L; } } }
    private void resetTrip() {
        if (tracking) pauseTracking(); totalMeters = 0f; maxSpeedKmh = 0f; trackedSeconds = 0; lastLocation = null;
        statusView.setText("تم تصفير الرحلة. اضغط بدء الرحلة للتسجيل."); refreshDashboard(); saveSession();
    }

    private void refreshDashboard() {
        speedView.setText(String.format(Locale.US, "%.0f", tracking && lastLocation != null && lastLocation.hasSpeed() ? lastLocation.getSpeed() * 3.6f : 0f));
        distanceView.setText("المسافة\n" + String.format(Locale.US, "%.2f كم", totalMeters / 1000f));
        timeView.setText("المدة\n" + formatDuration(trackedSeconds));
        maxSpeedView.setText("الأعلى\n" + String.format(Locale.US, "%.0f كم/س", maxSpeedKmh));
        startButton.setText(tracking ? "إيقاف مؤقت" : (totalMeters > 0 ? "متابعة الرحلة" : "بدء الرحلة"));
        startButton.setBackground(round(tracking ? Color.rgb(221, 103, 68) : Color.rgb(27, 174, 128), 16));
    }

    private String formatDuration(long seconds) { return String.format(Locale.US, "%02d:%02d", seconds / 60L, seconds % 60L); }
    private void loadSession() { SharedPreferences p = getSharedPreferences(PREFS, MODE_PRIVATE); totalMeters = p.getFloat(KEY_DISTANCE, 0f); trackedSeconds = p.getLong(KEY_SECONDS, 0L); maxSpeedKmh = p.getFloat(KEY_MAX_SPEED, 0f); tracking = false; }
    private void saveSession() { getSharedPreferences(PREFS, MODE_PRIVATE).edit().putFloat(KEY_DISTANCE, totalMeters).putLong(KEY_SECONDS, trackedSeconds).putFloat(KEY_MAX_SPEED, maxSpeedKmh).putBoolean(KEY_RUNNING, tracking).apply(); }

    @Override public void onProviderEnabled(String provider) { statusView.setText("تم تفعيل " + provider); }
    @Override public void onProviderDisabled(String provider) { statusView.setText("فعّل الموقع من الإعدادات لاستمرار التتبع"); }
    @Override public void onStatusChanged(String provider, int status, Bundle extras) { }
    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) { super.onRequestPermissionsResult(requestCode, permissions, results); if (requestCode == REQ_LOCATION && results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) { startTracking(); refreshDashboard(); } else { tracking = false; statusView.setText("صلاحية الموقع مطلوبة لتسجيل الرحلة"); refreshDashboard(); } }
    @Override protected void onPause() { super.onPause(); if (tracking) { addElapsed(); saveSession(); } }
    @Override protected void onDestroy() { super.onDestroy(); if (locationManager != null) try { locationManager.removeUpdates(this); } catch (Exception ignored) { } }

    private LinearLayout card() { LinearLayout c = new LinearLayout(this); c.setPadding(dp(14), dp(14), dp(14), dp(14)); c.setBackground(round(Color.rgb(27, 49, 67), 22)); return c; }
    private TextView statCard(String label, String value) { TextView v = text(label + "\n" + value, 15, Color.WHITE, true); v.setGravity(Gravity.CENTER); v.setPadding(dp(4), dp(15), dp(4), dp(15)); v.setBackground(round(Color.rgb(30, 57, 78), 16)); return v; }
    private TextView text(String value, int size, int color, boolean bold) { TextView t = new TextView(this); t.setText(value); t.setTextSize(size); t.setTextColor(color); t.setTypeface(Typeface.DEFAULT, bold ? Typeface.BOLD : Typeface.NORMAL); return t; }
    private Button button(String label, int color) { Button b = new Button(this); b.setText(label); b.setTextColor(Color.WHITE); b.setTextSize(17); b.setAllCaps(false); b.setTypeface(Typeface.DEFAULT, Typeface.BOLD); b.setBackground(round(color, 16)); return b; }
    private GradientDrawable round(int color, int radius) { GradientDrawable d = new GradientDrawable(); d.setColor(color); d.setCornerRadius(dp(radius)); return d; }
    private int dp(int value) { return (int) (value * getResources().getDisplayMetrics().density + 0.5f); }
    private View space(int width) { View v = new View(this); v.setLayoutParams(fixed(width)); return v; }
    private LinearLayout.LayoutParams match() { return new LinearLayout.LayoutParams(-1, -2); }
    private LinearLayout.LayoutParams matchWithTop(int top) { LinearLayout.LayoutParams p = match(); p.topMargin = dp(top); return p; }
    private LinearLayout.LayoutParams fixed(int width) { return new LinearLayout.LayoutParams(dp(width), 1); }
    private LinearLayout.LayoutParams weight() { return new LinearLayout.LayoutParams(0, -2, 1f); }
}