package com.explapp.gpstripmeterlegacy;

import android.media.AudioManager;
import android.media.ToneGenerator;
import android.os.Bundle;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

/** Lightweight interaction sounds for the Android 4.4 build. */
public class SoundMainActivity extends MainActivity {
    private ToneGenerator tones;
    private float downX;
    private float downY;
    private long lastSoundAt;

    @Override protected void onCreate(Bundle savedInstanceState) {
        tones = new ToneGenerator(AudioManager.STREAM_MUSIC, 48);
        super.onCreate(savedInstanceState);
    }

    @Override public boolean dispatchTouchEvent(MotionEvent event) {
        if (event.getAction() == MotionEvent.ACTION_DOWN) {
            downX = event.getRawX();
            downY = event.getRawY();
        } else if (event.getAction() == MotionEvent.ACTION_UP
                && Math.abs(event.getRawX() - downX) < 18f
                && Math.abs(event.getRawY() - downY) < 18f) {
            View target = findView(getWindow().getDecorView(), event.getRawX(), event.getRawY());
            if (target != null && target.isClickable()) playFor(target);
        }
        return super.dispatchTouchEvent(event);
    }

    private void playFor(View view) {
        if (tones == null || System.currentTimeMillis() - lastSoundAt < 70L) return;
        lastSoundAt = System.currentTimeMillis();
        String text = view instanceof TextView ? ((TextView) view).getText().toString() : "";
        if (containsAny(text, "بدء", "تشغيل", "حفظ", "استكمال")) {
            tones.startTone(ToneGenerator.TONE_PROP_ACK, 115);
        } else if (containsAny(text, "إيقاف", "إيقاف مؤقت", "رجوع", "العودة")) {
            tones.startTone(ToneGenerator.TONE_PROP_BEEP2, 85);
        } else if (containsAny(text, "حذف", "مسح", "إلغاء")) {
            tones.startTone(ToneGenerator.TONE_PROP_NACK, 110);
        } else {
            tones.startTone(ToneGenerator.TONE_PROP_BEEP, 60);
        }
    }

    private View findView(View view, float x, float y) {
        if (view == null || view.getVisibility() != View.VISIBLE) return null;
        int[] location = new int[2];
        view.getLocationOnScreen(location);
        if (x < location[0] || x > location[0] + view.getWidth()
                || y < location[1] || y > location[1] + view.getHeight()) return null;
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = group.getChildCount() - 1; i >= 0; i--) {
                View child = findView(group.getChildAt(i), x, y);
                if (child != null) return child;
            }
        }
        return view;
    }

    private boolean containsAny(String text, String... words) {
        for (String word : words) if (text.contains(word)) return true;
        return false;
    }

    @Override protected void onDestroy() {
        if (tones != null) {
            tones.release();
            tones = null;
        }
        super.onDestroy();
    }
}
