// =============================================================
// ox_lib_secure
// File: html/js/sounds.js
// Description:
//   نظام الأصوات لنظام الإشعارات.
//   يدير تشغيل الأصوات المصاحبة لكل نوع إشعار.
//
// Notes:
//   - يستخدم Web Audio API للأداء العالي.
//   - يدعم أصوات مخصصة أو افتراضية.
//   - يوفر التحكم في مستوى الصوت وكتمه.
//   - يتكامل مع app.js عبر window.OxSecureSounds.
//   - تم إصلاح: إزالة activeSounds غير المستخدمة،
//     استخدام نسخ متعددة للأصوات لمنع التداخل،
//     تتبع مؤقتات الصوت الحرج لإلغائها.
// =============================================================

(function() {
    'use strict';

    // =============================================================
    // المتغيرات العامة
    // =============================================================
    let audioContext = null;
    let masterGain = null;
    let isMuted = false;
    let volume = 0.7; // مستوى الصوت الافتراضي (70%)
    let soundCache = new Map(); // لتخزين كائنات Audio للأصوات المخصصة
    let criticalTimeouts = []; // مؤقتات الصوت الحرج النشطة

    // إعدادات الأصوات
    const SOUND_SETTINGS = {
        info: {
            frequency: 800,
            duration: 0.15,
            type: 'sine',
            attack: 0.01,
            decay: 0.1
        },
        success: {
            frequency: 1000,
            duration: 0.2,
            type: 'sine',
            attack: 0.01,
            decay: 0.15
        },
        warning: {
            frequency: 600,
            duration: 0.25,
            type: 'triangle',
            attack: 0.02,
            decay: 0.2
        },
        error: {
            frequency: 400,
            duration: 0.3,
            type: 'sawtooth',
            attack: 0.02,
            decay: 0.25
        },
        critical: {
            frequency: 300,
            duration: 0.5,
            type: 'square',
            attack: 0.05,
            decay: 0.4,
            repeat: 3,
            interval: 0.15
        },
        default: {
            frequency: 700,
            duration: 0.15,
            type: 'sine',
            attack: 0.01,
            decay: 0.1
        },
        notification: {
            frequency: 880,
            duration: 0.12,
            type: 'sine',
            attack: 0.005,
            decay: 0.1
        }
    };

    // =============================================================
    // تهيئة Web Audio API
    // =============================================================
    function initAudioContext() {
        if (audioContext) return true;

        try {
            const AudioContext = window.AudioContext || window.webkitAudioContext;

            if (!AudioContext) {
                console.warn('[ox_lib_secure] Web Audio API not supported.');
                return false;
            }

            audioContext = new AudioContext();
            masterGain = audioContext.createGain();
            masterGain.connect(audioContext.destination);
            masterGain.gain.value = volume;

            return true;
        } catch (err) {
            console.error('[ox_lib_secure] Failed to initialize AudioContext:', err);
            return false;
        }
    }

    // =============================================================
    // تشغيل نغمة مولدة (Synthesized Tone)
    // =============================================================
    function playTone(settings) {
        if (!initAudioContext()) return false;
        if (isMuted) return false;

        // استئناف السياق إذا كان معلقًا
        if (audioContext.state === 'suspended') {
            audioContext.resume();
        }

        try {
            const oscillator = audioContext.createOscillator();
            const gainNode = audioContext.createGain();

            oscillator.type = settings.type || 'sine';
            oscillator.frequency.value = settings.frequency || 800;

            // مغلف الصوت (Envelope)
            const now = audioContext.currentTime;
            const attack = settings.attack || 0.01;
            const decay = settings.decay || 0.1;

            gainNode.gain.setValueAtTime(0, now);
            gainNode.gain.linearRampToValueAtTime(0.3, now + attack);
            gainNode.gain.exponentialRampToValueAtTime(0.001, now + attack + decay);

            oscillator.connect(gainNode);
            gainNode.connect(masterGain);

            oscillator.start(now);
            oscillator.stop(now + attack + decay + 0.05);

            return true;
        } catch (err) {
            console.error('[ox_lib_secure] Failed to play tone:', err);
            return false;
        }
    }

    // =============================================================
    // تشغيل صوت حرج (متكرر) مع تتبع المؤقتات
    // =============================================================
    function playCriticalSound(settings) {
        if (!initAudioContext()) return false;
        if (isMuted) return false;

        const repeatCount = settings.repeat || 3;
        const interval = settings.interval || 0.15;

        for (let i = 0; i < repeatCount; i++) {
            const timeoutId = setTimeout(function() {
                playTone(settings);
                // إزالة المؤقت من القائمة بعد التنفيذ
                const index = criticalTimeouts.indexOf(timeoutId);
                if (index > -1) {
                    criticalTimeouts.splice(index, 1);
                }
            }, i * (interval * 1000));

            criticalTimeouts.push(timeoutId);
        }

        return true;
    }

    // =============================================================
    // تشغيل صوت من ملف خارجي
    // =============================================================
    function playSoundFile(url, soundName) {
        if (isMuted) return false;

        try {
            // إنشاء كائن Audio جديد في كل مرة لمنع التداخل
            const audio = new Audio(url);
            audio.volume = volume;

            // إضافة إلى الكاش مع اسم مفتاح خاص للاسترجاع لاحقًا
            soundCache.set('file_' + soundName + '_' + Date.now(), audio);

            const playPromise = audio.play();

            if (playPromise !== undefined) {
                playPromise.catch(function(err) {
                    console.warn('[ox_lib_secure] Failed to play sound file:', err);
                });
            }

            return true;
        } catch (err) {
            console.error('[ox_lib_secure] Error playing sound file:', err);
            return false;
        }
    }

    // =============================================================
    // الدالة الرئيسية لتشغيل الأصوات
    // =============================================================
    function play(soundName) {
        if (!soundName) soundName = 'default';

        // التحقق من الأصوات المخصصة (ملفات خارجية)
        const customSoundPath = getCustomSoundPath(soundName);
        if (customSoundPath) {
            return playSoundFile(customSoundPath, soundName);
        }

        // البحث في الإعدادات
        const settings = SOUND_SETTINGS[soundName] || SOUND_SETTINGS.default;

        // الأصوات الحرجة تحتاج معالجة خاصة
        if (soundName === 'critical') {
            return playCriticalSound(settings);
        }

        return playTone(settings);
    }

    // =============================================================
    // الحصول على مسار الصوت المخصص
    // =============================================================
    function getCustomSoundPath(soundName) {
        // يمكن إضافة مسارات الأصوات المخصصة هنا
        // مثال: return 'sounds/' + soundName + '.mp3';
        return null;
    }

    // =============================================================
    // التحكم في مستوى الصوت
    // =============================================================
    function setVolume(newVolume) {
        volume = Math.max(0, Math.min(1, newVolume));

        if (masterGain) {
            masterGain.gain.value = volume;
        }

        // تحديث جميع كائنات الأصوات المخزنة
        soundCache.forEach(function(audio) {
            audio.volume = volume;
        });

        return volume;
    }

    // =============================================================
    // كتم الصوت
    // =============================================================
    function mute() {
        isMuted = true;
        return true;
    }

    // =============================================================
    // إلغاء كتم الصوت
    // =============================================================
    function unmute() {
        isMuted = false;
        return true;
    }

    // =============================================================
    // التحقق من حالة الكتم
    // =============================================================
    function isAudioMuted() {
        return isMuted;
    }

    // =============================================================
    // الحصول على مستوى الصوت الحالي
    // =============================================================
    function getVolume() {
        return volume;
    }

    // =============================================================
    // إيقاف جميع الأصوات النشطة
    // =============================================================
    function stopAll() {
        // إلغاء جميع مؤقتات الصوت الحرج
        criticalTimeouts.forEach(function(timeoutId) {
            clearTimeout(timeoutId);
        });
        criticalTimeouts = [];

        // إيقاف جميع كائنات الأصوات المحفوظة
        soundCache.forEach(function(audio) {
            audio.pause();
            audio.currentTime = 0;
        });
    }

    // =============================================================
    // مسح كاش الأصوات
    // =============================================================
    function clearCache() {
        stopAll();
        soundCache.clear();
    }

    // =============================================================
    // إضافة صوت مخصص
    // =============================================================
    function addCustomSound(name, url) {
        if (!name || !url) return false;

        try {
            const audio = new Audio(url);
            audio.volume = volume;
            soundCache.set('custom_' + name, audio);
            return true;
        } catch (err) {
            console.error('[ox_lib_secure] Failed to add custom sound:', err);
            return false;
        }
    }

    // =============================================================
    // تشغيل صوت مخصص
    // =============================================================
    function playCustom(name) {
        const audio = soundCache.get('custom_' + name);

        if (!audio) {
            console.warn('[ox_lib_secure] Custom sound not found:', name);
            return false;
        }

        if (isMuted) return false;

        try {
            audio.currentTime = 0;
            const playPromise = audio.play();

            if (playPromise !== undefined) {
                playPromise.catch(function(err) {
                    console.warn('[ox_lib_secure] Failed to play custom sound:', err);
                });
            }

            return true;
        } catch (err) {
            console.error('[ox_lib_secure] Error playing custom sound:', err);
            return false;
        }
    }

    // =============================================================
    // تصدير الوحدة العامة
    // =============================================================
    window.OxSecureSounds = {
        play: play,
        setVolume: setVolume,
        getVolume: getVolume,
        mute: mute,
        unmute: unmute,
        isMuted: isAudioMuted,
        stopAll: stopAll,
        clearCache: clearCache,
        addCustom: addCustomSound,
        playCustom: playCustom,
        
        // معلومات للمطورين
        info: {
            version: '1.0.0',
            supportedTypes: Object.keys(SOUND_SETTINGS),
            audioContextSupported: !!(window.AudioContext || window.webkitAudioContext)
        }
    };

    // =============================================================
    // التهيئة عند تحميل الصفحة
    // =============================================================
    console.log('[ox_lib_secure] Sound system loaded.');
    console.log('[ox_lib_secure] Available sound types:', Object.keys(SOUND_SETTINGS).join(', '));

})();
