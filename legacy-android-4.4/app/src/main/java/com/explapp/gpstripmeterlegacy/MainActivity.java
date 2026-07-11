package com.explapp.gpstripmeterlegacy;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.LinearLayout;
import android.widget.TextView;

public class MainActivity extends Activity implements LocationListener {
    private static final int REQ_LOCATION = 10;
    private TextView speedView;
    private TextView distanceView;
    private TextView statusView;
    private Location lastLocation;
    private float totalMeters = 0f;
    private LocationManager locationManager;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setPadding(24, 24, 24, 24);
        root.setBackgroundColor(Color.rgb(20, 24, 28));

        TextView title = makeText("عداد الرحلة GPS", 28);
        speedView = makeText("0 كم/س", 48);
        distanceView = makeText("المسافة: 0.00 كم", 26);
        statusView = makeText("بانتظار إشارة GPS…", 18);

        root.addView(title);
        root.addView(speedView);
        root.addView(distanceView);
        root.addView(statusView);
        setContentView(root);

        locationManager = (LocationManager) getSystemService(LOCATION_SERVICE);
        requestLocationUpdatesSafely();
    }

    private TextView makeText(String text, int size) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextColor(Color.WHITE);
        view.setTextSize(size);
        view.setGravity(Gravity.CENTER);
        view.setPadding(8, 20, 8, 20);
        return view;
    }

    private void requestLocationUpdatesSafely() {
        if (android.os.Build.VERSION.SDK_INT >= 23 && checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION}, REQ_LOCATION);
            return;
        }
        try {
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 1f, this);
            statusView.setText("GPS يعمل");
        } catch (Exception e) {
            statusView.setText("تعذر تشغيل GPS");
        }
    }

    @Override
    public void onLocationChanged(Location location) {
        float speedKmh = location.hasSpeed() ? location.getSpeed() * 3.6f : 0f;
        speedView.setText(String.format(java.util.Locale.US, "%.0f كم/س", speedKmh));

        if (lastLocation != null && location.getAccuracy() <= 50f) {
            float delta = lastLocation.distanceTo(location);
            if (delta >= 1f && delta < 200f) totalMeters += delta;
        }
        lastLocation = location;
        distanceView.setText(String.format(java.util.Locale.US, "المسافة: %.2f كم", totalMeters / 1000f));
        statusView.setText(String.format(java.util.Locale.US, "الدقة: %.0f م", location.getAccuracy()));
    }

    @Override public void onStatusChanged(String provider, int status, Bundle extras) {}
    @Override public void onProviderEnabled(String provider) { statusView.setText("GPS يعمل"); }
    @Override public void onProviderDisabled(String provider) { statusView.setText("فعّل GPS من الإعدادات"); }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQ_LOCATION && grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            requestLocationUpdatesSafely();
        } else {
            statusView.setText("صلاحية الموقع مطلوبة");
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (locationManager != null) {
            try { locationManager.removeUpdates(this); } catch (Exception ignored) {}
        }
    }
}
