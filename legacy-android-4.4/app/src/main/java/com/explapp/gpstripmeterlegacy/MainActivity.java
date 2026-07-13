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
import android.view.animation.AlphaAnimation;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class MainActivity extends Activity implements LocationListener {
    private static final int REQ_LOCATION = 10;
    private static final String PREFS = "legacy_trip";
    private static final String KEY_DISTANCE = "distance";
    private static final String KEY_SECONDS = "seconds";
    private static final String KEY_MAX_SPEED = "max_speed";
    private static final String KEY_RUNNING = "running";
    private static final String KEY_HISTORY = "history";

    private TextView distanceView, timeView, maxSpeedView, averageSpeedView, statusView, startButton;
    private SpeedGauge speedGauge;
    private LocationManager locationManager;
    private Location lastLocation;
    private float totalMeters, maxSpeedKmh, currentSpeedKmh;
    private long trackedSeconds, startedAt;
    private long lastSavedSecond;
    private boolean tracking;
    private FrameLayout screenHost;
    private TextView headerTitle, headerSubtitle, dashboardNav, historyNav, settingsNav;
    private int activeScreen;
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
        if (android.os.Build.VERSION.SDK_INT >= 17) root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        GradientDrawable background = new GradientDrawable(GradientDrawable.Orientation.TL_BR,
                new int[]{Color.rgb(7, 17, 31), Color.rgb(15, 45, 66)});
        root.setBackground(background);

        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.VERTICAL);
        header.setPadding(dp(16), dp(12), dp(16), dp(10));
        headerTitle = text("عداد الرحلة", 24, Color.WHITE, true);
        headerSubtitle = text("GPS • سريع وخفيف لأجهزة Android 4.4", 13, Color.rgb(167, 205, 235), false);
        headerSubtitle.setPadding(0, dp(3), 0, 0);
        header.addView(headerTitle);
        header.addView(headerSubtitle);
        root.addView(header, match());

        screenHost = new FrameLayout(this);
        root.addView(screenHost, new LinearLayout.LayoutParams(-1, 0, 1f));

        LinearLayout navigation = new LinearLayout(this);
        navigation.setPadding(dp(8), dp(5), dp(8), dp(7));
        navigation.setBackgroundColor(Color.rgb(12, 30, 45));
        dashboardNav = navItem("●\nالعداد", 0);
        historyNav = navItem("▤\nالرحلات", 1);
        settingsNav = navItem("◆\nالإعدادات", 2);
        navigation.addView(dashboardNav, new LinearLayout.LayoutParams(0, dp(55), 1f));
        navigation.addView(historyNav, new LinearLayout.LayoutParams(0, dp(55), 1f));
        navigation.addView(settingsNav, new LinearLayout.LayoutParams(0, dp(55), 1f));
        root.addView(navigation);
        setContentView(root);
        locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
        showScreen(0);
    }

    private View buildDashboard() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(12), dp(4), dp(12), dp(10));

        speedGauge = new SpeedGauge(this);
        int heightDp = (int) (getResources().getDisplayMetrics().heightPixels / getResources().getDisplayMetrics().density);
        root.addView(speedGauge, new LinearLayout.LayoutParams(-1, dp(heightDp < 560 ? 176 : 210)));

        LinearLayout stats = new LinearLayout(this);
        stats.setOrientation(LinearLayout.HORIZONTAL);
        stats.setPadding(0, dp(12), 0, dp(8));
        distanceView = statCard("المسافة", "0.00 كم");
        timeView = statCard("المدة", "00:00");
        maxSpeedView = statCard("أعلى سرعة", "0 كم/س");
        stats.addView(distanceView, weight()); stats.addView(space(8), fixed(8));
        stats.addView(timeView, weight()); stats.addView(space(8), fixed(8)); stats.addView(maxSpeedView, weight());
        root.addView(stats, match());

        averageSpeedView = statCard("متوسط السرعة", "0 كم/س");
        averageSpeedView.setPadding(dp(4), dp(9), dp(4), dp(9));
        LinearLayout.LayoutParams averageParams = match();
        averageParams.bottomMargin = dp(8);
        root.addView(averageSpeedView, averageParams);

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
        Button finish = button("حفظ وإنهاء", Color.rgb(180, 83, 9));
        finish.setTextSize(15);
        finish.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { finishTrip(); } });
        secondary.addView(finish, weight());
        secondary.addView(space(8), fixed(8));
        Button settings = button("إعدادات GPS", Color.rgb(54, 91, 125));
        settings.setTextSize(15);
        settings.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { try { startActivity(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)); } catch (Exception ignored) { statusView.setText("تعذر فتح إعدادات الموقع على هذا الجهاز"); } } });
        secondary.addView(settings, weight());
        root.addView(secondary, match());

        TextView footer = text("تُحفظ الرحلة تلقائيًا، ويتوقف GPS عند مغادرة التطبيق لتوفير البطارية.", 12, Color.rgb(141, 175, 199), false);
        footer.setGravity(Gravity.CENTER); footer.setPadding(0, dp(12), 0, 0); root.addView(footer, match());
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true); scroll.setBackgroundColor(Color.rgb(7, 17, 31)); scroll.addView(root);
        return scroll;
    }

    private TextView navItem(String label, final int destination) {
        TextView item = text(label, 11, Color.rgb(141, 175, 199), true);
        item.setGravity(Gravity.CENTER);
        item.setLines(2);
        item.setBackground(round(Color.TRANSPARENT, 14));
        item.setOnClickListener(new View.OnClickListener() { @Override public void onClick(View v) { showScreen(destination); } });
        return item;
    }

    private void showScreen(int destination) {
        if (tracking && destination != 0) { statusView.setText("أوقف الرحلة مؤقتاً قبل فتح القوائم"); return; }
        activeScreen = destination;
        screenHost.removeAllViews();
        View screen = destination == 1 ? buildHistory() : destination == 2 ? buildSettings() : buildDashboard();
        screenHost.addView(screen, new FrameLayout.LayoutParams(-1, -1));
        AlphaAnimation animation = new AlphaAnimation(.25f, 1f); animation.setDuration(180); screen.startAnimation(animation);
        dashboardNav.setTextColor(destination == 0 ? Color.rgb(34, 211, 238) : Color.rgb(141, 175, 199));
        historyNav.setTextColor(destination == 1 ? Color.rgb(34, 211, 238) : Color.rgb(141, 175, 199));
        settingsNav.setTextColor(destination == 2 ? Color.rgb(34, 211, 238) : Color.rgb(141, 175, 199));
        dashboardNav.setBackground(round(destination == 0 ? Color.rgb(27, 60, 78) : Color.TRANSPARENT, 14));
        historyNav.setBackground(round(destination == 1 ? Color.rgb(27, 60, 78) : Color.TRANSPARENT, 14));
        settingsNav.setBackground(round(destination == 2 ? Color.rgb(27, 60, 78) : Color.TRANSPARENT, 14));
        if (destination == 0) { headerTitle.setText("عداد الرحلة"); headerSubtitle.setText("GPS • لوحة القيادة المباشرة"); }
        else if (destination == 1) { headerTitle.setText("سجل الرحلات"); headerSubtitle.setText("ملخصات محفوظة على الجهاز"); }
        else { headerTitle.setText("الإعدادات"); headerSubtitle.setText("الموقع والبيانات الحالية"); }
        if (destination == 0) refreshDashboard();
    }

    private View buildHistory() {
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true);
        LinearLayout list = new LinearLayout(this); list.setOrientation(LinearLayout.VERTICAL); list.setPadding(dp(12), dp(10), dp(12), dp(12));
        String history = getSharedPreferences(PREFS, MODE_PRIVATE).getString(KEY_HISTORY, "");
        if (history.length() == 0) {
            TextView emptyIcon = text("◎", 64, Color.rgb(34, 211, 238), true); emptyIcon.setGravity(Gravity.CENTER); emptyIcon.setPadding(0, dp(50), 0, dp(8)); list.addView(emptyIcon);
            TextView empty = text("لا توجد رحلات محفوظة\nأنهِ رحلة من لوحة العداد لتظهر هنا", 16, Color.WHITE, true); empty.setGravity(Gravity.CENTER); list.addView(empty);
        } else {
            String[] records = history.split(";");
            for (int i = 0; i < records.length; i++) {
                String[] data = records[i].split(",");
                if (data.length != 4) continue;
                LinearLayout card = new LinearLayout(this); card.setOrientation(LinearLayout.VERTICAL); card.setPadding(dp(16), dp(14), dp(16), dp(14)); card.setBackground(round(Color.rgb(27, 49, 67), 18));
                try {
                    TextView date = text(new SimpleDateFormat("dd MMM yyyy • HH:mm", new Locale("ar")).format(new Date(Long.parseLong(data[0]))), 15, Color.WHITE, true); card.addView(date);
                    TextView values = text(String.format(Locale.US, "%.2f كم   •   %s   •   أعلى %s كم/س", Float.parseFloat(data[1]) / 1000f, formatDuration(Long.parseLong(data[2])), data[3]), 13, Color.rgb(148, 225, 219), false); values.setPadding(0, dp(7), 0, 0); card.addView(values);
                } catch (NumberFormatException invalidRecord) { continue; }
                LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(-1, -2); cp.setMargins(0, dp(5), 0, dp(5)); list.addView(card, cp);
            }
        }
        scroll.addView(list); return scroll;
    }

    private View buildSettings() {
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true);
        LinearLayout page = new LinearLayout(this); page.setOrientation(LinearLayout.VERTICAL); page.setPadding(dp(12), dp(10), dp(12), dp(12));
        page.addView(settingCard("حالة الرحلة الحالية", String.format(Locale.US, "%.2f كم • %s • أعلى %.0f كم/س", totalMeters / 1000f, formatDuration(trackedSeconds), maxSpeedKmh)));
        Button gps = button("فتح إعدادات GPS", Color.rgb(54, 91, 125)); gps.setOnClickListener(new View.OnClickListener() { @Override public void onClick(View v) { try { startActivity(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)); } catch (Exception ignored) { } } }); page.addView(gps, matchWithTop(12));
        Button reset = button("تصفير الرحلة الحالية", Color.rgb(180, 83, 9)); reset.setOnClickListener(new View.OnClickListener() { @Override public void onClick(View v) { confirmReset(); } }); page.addView(reset, matchWithTop(8));
        Button clear = button("مسح سجل الرحلات", Color.rgb(67, 91, 112)); clear.setOnClickListener(new View.OnClickListener() { @Override public void onClick(View v) { confirmClearHistory(); } }); page.addView(clear, matchWithTop(8));
        page.addView(settingCard("الخصوصية والبطارية", "تبقى جميع الرحلات على جهازك. يتوقف GPS عند مغادرة التطبيق، ولا توجد خدمات تعمل في الخلفية."), matchWithTop(16));
        scroll.addView(page); return scroll;
    }

    private View settingCard(String title, String detail) {
        LinearLayout card = new LinearLayout(this); card.setOrientation(LinearLayout.VERTICAL); card.setPadding(dp(16), dp(14), dp(16), dp(14)); card.setBackground(round(Color.rgb(27, 49, 67), 18));
        card.addView(text(title, 16, Color.WHITE, true)); TextView d = text(detail, 13, Color.rgb(167, 205, 235), false); d.setPadding(0, dp(6), 0, 0); card.addView(d); return card;
    }

    private void toggleTracking() { if (tracking) pauseTracking(); else beginTracking(); }

    private void finishTrip() {
        if (totalMeters < 1f && trackedSeconds < 1L) { Toast.makeText(this, "ابدأ رحلة أولاً قبل الحفظ", Toast.LENGTH_SHORT).show(); return; }
        if (tracking) pauseTracking();
        String record = System.currentTimeMillis() + "," + totalMeters + "," + trackedSeconds + "," + Math.round(maxSpeedKmh);
        SharedPreferences preferences = getSharedPreferences(PREFS, MODE_PRIVATE);
        String old = preferences.getString(KEY_HISTORY, "");
        String combined = old.length() == 0 ? record : record + ";" + old;
        String[] records = combined.split(";");
        StringBuilder trimmed = new StringBuilder();
        for (int i = 0; i < records.length && i < 20; i++) { if (i > 0) trimmed.append(';'); trimmed.append(records[i]); }
        preferences.edit().putString(KEY_HISTORY, trimmed.toString()).apply();
        totalMeters = 0f; maxSpeedKmh = 0f; trackedSeconds = 0L; lastLocation = null; saveSession();
        Toast.makeText(this, "تم حفظ ملخص الرحلة", Toast.LENGTH_SHORT).show();
        showScreen(1);
    }

    private void confirmClearHistory() {
        new AlertDialog.Builder(this).setTitle("مسح سجل الرحلات؟").setMessage("سيتم حذف جميع الملخصات المحفوظة على هذا الجهاز.")
                .setNegativeButton("إلغاء", null).setPositiveButton("مسح", new DialogInterface.OnClickListener() {
                    @Override public void onClick(DialogInterface dialog, int which) {
                        getSharedPreferences(PREFS, MODE_PRIVATE).edit().remove(KEY_HISTORY).apply();
                        Toast.makeText(MainActivity.this, "تم مسح السجل", Toast.LENGTH_SHORT).show(); showScreen(1);
                    }
                }).show();
    }

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
                    @Override public void onClick(DialogInterface dialog, int which) { resetTrip(); if (activeScreen == 2) showScreen(2); }
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

    private String formatDuration(long seconds) {
        long hours = seconds / 3600L, minutes = (seconds % 3600L) / 60L;
        return hours > 0 ? String.format(Locale.US, "%02d:%02d:%02d", hours, minutes, seconds % 60L) : String.format(Locale.US, "%02d:%02d", minutes, seconds % 60L);
    }
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
    @Override public void onBackPressed() { if (activeScreen != 0) showScreen(0); else super.onBackPressed(); }

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
