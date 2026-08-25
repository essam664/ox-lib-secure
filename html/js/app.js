// =============================================================
// ox_lib_secure
// File: html/js/app.js
// Description:
//   منطق الواجهة الرئيسي لنظام الإشعارات.
//   يستقبل الرسائل من FiveM ويدير عرض الإشعارات.
//
// Notes:
//   - يستقبل الرسائل عبر window.addEventListener('message').
//   - يدير دورة حياة الإشعار من العرض إلى الإزالة.
//   - يدعم أنماط متعددة ومواقع مختلفة.
//   - يتكامل مع نظام الأصوات (sounds.js).
//   - إصلاح: فحوصات وجود العناصر قبل الاستخدام.
// =============================================================

(function() {
    'use strict';

    // =============================================================
    // المتغيرات العامة
    // =============================================================
    let notificationsContainer = document.getElementById('notifications-container');
    let criticalContainer = document.getElementById('critical-container');
    let criticalTitle = document.getElementById('critical-title');
    let criticalBody = document.getElementById('critical-body');
    let criticalCloseBtn = document.getElementById('critical-close');
    let notificationTemplate = document.getElementById('notification-template');

    // قائمة الإشعارات النشطة
    let activeNotifications = new Map();
    let notificationCounter = 0;

    // إعدادات عامة
    const DEFAULT_DURATION = 5000;
    const MAX_VISIBLE_NOTIFICATIONS = 5;

    // حالة الواجهة
    let uiReady = false;

    // =============================================================
    // أدوات مساعدة
    // =============================================================
    function generateId() {
        return 'notif_' + (++notificationCounter) + '_' + Date.now();
    }

    function getIconForType(type) {
        const templateId = 'icon-' + type;
        const template = document.getElementById(templateId);

        if (template) {
            return template.innerHTML;
        }

        // أيقونة افتراضية
        const defaultTemplate = document.getElementById('icon-info');
        return defaultTemplate ? defaultTemplate.innerHTML : '';
    }

    function escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    // =============================================================
    // إصلاح: إنشاء العناصر الديناميكية إذا لم تكن موجودة
    // =============================================================
    function ensureDOMElements() {
        // إنشاء حاوية الإشعارات إذا لم تكن موجودة
        if (!notificationsContainer) {
            console.warn('[ox_lib_secure] notifications-container not found, creating dynamically.');
            notificationsContainer = document.createElement('div');
            notificationsContainer.id = 'notifications-container';
            notificationsContainer.className = 'notifications-container';
            document.body.appendChild(notificationsContainer);
        }

        // إنشاء قالب الإشعار إذا لم يكن موجودًا
        if (!notificationTemplate) {
            console.warn('[ox_lib_secure] notification-template not found, creating dynamically.');
            notificationTemplate = document.createElement('template');
            notificationTemplate.id = 'notification-template';
            notificationTemplate.innerHTML = `
                <div class="notification">
                    <div class="notification-progress"></div>
                    <div class="notification-icon"></div>
                    <div class="notification-content">
                        <div class="notification-title"></div>
                        <div class="notification-body"></div>
                    </div>
                    <button class="notification-close">&times;</button>
                </div>
            `;
            document.body.appendChild(notificationTemplate);
        }

        // إنشاء حاوية الإشعار الحرج إذا لم تكن موجودة
        if (!criticalContainer) {
            console.warn('[ox_lib_secure] critical-container not found, creating dynamically.');
            criticalContainer = document.createElement('div');
            criticalContainer.id = 'critical-container';
            criticalContainer.className = 'critical-container hidden';
            criticalContainer.innerHTML = `
                <div class="critical-overlay"></div>
                <div class="critical-content">
                    <div class="critical-icon">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
                            <line x1="12" y1="9" x2="12" y2="13"/>
                            <line x1="12" y1="17" x2="12.01" y2="17"/>
                        </svg>
                    </div>
                    <h2 id="critical-title"></h2>
                    <p id="critical-body"></p>
                    <button id="critical-close" class="critical-btn">حسنًا</button>
                </div>
            `;
            document.body.appendChild(criticalContainer);

            // تحديث المراجع
            criticalTitle = document.getElementById('critical-title');
            criticalBody = document.getElementById('critical-body');
            criticalCloseBtn = document.getElementById('critical-close');
        }
    }

    // =============================================================
    // إشعار الواجهة بأنها جاهزة
    // =============================================================
    function notifyUIReady() {
        fetch('https://ox_lib_secure/uiReady', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ ready: true })
        }).catch(function(err) {
            console.warn('[ox_lib_secure] Failed to notify UI ready:', err);
        });
    }

    // =============================================================
    // عرض إشعار واحد
    // =============================================================
    function showNotification(data) {
        // إصلاح: التحقق من وجود العناصر الأساسية
        if (!notificationsContainer || !notificationTemplate) {
            console.error('[ox_lib_secure] Cannot show notification: DOM elements not ready.');
            ensureDOMElements();

            // إعادة المحاولة بعد إنشاء العناصر
            if (!notificationsContainer || !notificationTemplate) {
                return null;
            }
        }

        const id = data.id || generateId();

        // التحقق من الحد الأقصى
        if (activeNotifications.size >= MAX_VISIBLE_NOTIFICATIONS) {
            removeOldestNotification();
        }

        try {
            // إنشاء عنصر الإشعار من القالب
            const clone = notificationTemplate.content.cloneNode(true);
            const notificationEl = clone.querySelector('.notification');

            if (!notificationEl) {
                console.error('[ox_lib_secure] Failed to clone notification template.');
                return null;
            }

            // تعيين المعرف
            notificationEl.dataset.id = id;

            // تعيين النمط (نوع الإشعار)
            const type = data.type || 'info';
            notificationEl.classList.add('type-' + type);

            // تعيين نمط التصميم
            if (data.designStyle && data.designStyle !== 'default') {
                notificationEl.classList.add('style-' + data.designStyle);
            }

            // تعيين الأيقونة
            const iconEl = notificationEl.querySelector('.notification-icon');
            if (iconEl) {
                iconEl.innerHTML = getIconForType(type);
            }

            // تعيين المحتوى
            const titleEl = notificationEl.querySelector('.notification-title');
            const bodyEl = notificationEl.querySelector('.notification-body');

            if (titleEl) {
                titleEl.textContent = data.title || '';
                if (!data.title) {
                    titleEl.style.display = 'none';
                }
            }

            if (bodyEl) {
                bodyEl.textContent = data.body || '';
                if (!data.body) {
                    bodyEl.style.display = 'none';
                }
            }

            // إعداد شريط التقدم
            const progressEl = notificationEl.querySelector('.notification-progress');
            const duration = data.durationMs || DEFAULT_DURATION;
            if (progressEl) {
                progressEl.style.animationDuration = duration + 'ms';
            }

            // زر الإغلاق
            const closeBtn = notificationEl.querySelector('.notification-close');
            if (closeBtn) {
                closeBtn.addEventListener('click', function(e) {
                    e.stopPropagation();
                    removeNotification(id);
                });
            }

            // إضافة الإشعار إلى الحاوية
            notificationsContainer.appendChild(clone);

            // حفظ في القائمة النشطة
            activeNotifications.set(id, {
                element: notificationEl,
                timeout: null
            });

            // جدولة الإزالة التلقائية
            const timeoutId = setTimeout(function() {
                removeNotification(id);
            }, duration + 300);

            activeNotifications.get(id).timeout = timeoutId;

            // تشغيل الصوت
            if (data.sound !== false && window.OxSecureSounds) {
                window.OxSecureSounds.play(data.soundName || type);
            }

            return id;
        } catch (err) {
            console.error('[ox_lib_secure] Error showing notification:', err);
            return null;
        }
    }

    // =============================================================
    // إزالة إشعار
    // =============================================================
    function removeNotification(id) {
        const notification = activeNotifications.get(id);

        if (!notification) return;

        // إلغاء المؤقت
        if (notification.timeout) {
            clearTimeout(notification.timeout);
        }

        // إضافة فئة الإزالة للأنيميشن
        if (notification.element) {
            notification.element.classList.add('removing');

            // إزالة العنصر بعد انتهاء الأنيميشن
            setTimeout(function() {
                if (notification.element && notification.element.parentNode) {
                    notification.element.parentNode.removeChild(notification.element);
                }
            }, 300);
        }

        // إزالة من القائمة النشطة
        activeNotifications.delete(id);
    }

    // =============================================================
    // إزالة أقدم إشعار
    // =============================================================
    function removeOldestNotification() {
        if (activeNotifications.size === 0) return;

        const oldestId = activeNotifications.keys().next().value;
        removeNotification(oldestId);
    }

    // =============================================================
    // إزالة جميع الإشعارات
    // =============================================================
    function removeAllNotifications() {
        const ids = Array.from(activeNotifications.keys());

        ids.forEach(function(id) {
            removeNotification(id);
        });
    }

    // =============================================================
    // عرض إشعار حرج (Critical)
    // =============================================================
    function showCritical(data) {
        // إصلاح: التحقق من وجود العناصر
        if (!criticalContainer || !criticalTitle || !criticalBody) {
            console.error('[ox_lib_secure] Cannot show critical notification: DOM elements not ready.');
            ensureDOMElements();

            if (!criticalContainer || !criticalTitle || !criticalBody) {
                return;
            }
        }

        try {
            criticalTitle.textContent = data.title || 'تنبيه حرج';
            criticalBody.textContent = data.body || '';

            criticalContainer.classList.remove('hidden');

            // تشغيل صوت حرج
            if (window.OxSecureSounds) {
                window.OxSecureSounds.play('critical');
            }
        } catch (err) {
            console.error('[ox_lib_secure] Error showing critical notification:', err);
        }
    }

    // =============================================================
    // إخفاء الإشعار الحرج
    // =============================================================
    function hideCritical() {
        if (criticalContainer) {
            criticalContainer.classList.add('hidden');
        }
    }

    // =============================================================
    // فتح/إغلاق الواجهة الرئيسية
    // =============================================================
    function openUI() {
        const mainUI = document.getElementById('main-ui');
        if (mainUI) {
            mainUI.classList.remove('hidden');
        }
    }

    function closeUI() {
        const mainUI = document.getElementById('main-ui');
        if (mainUI) {
            mainUI.classList.add('hidden');
        }

        // إشعار FiveM بإغلاق الواجهة
        fetch('https://ox_lib_secure/closeUI', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        }).catch(function(err) {
            console.warn('[ox_lib_secure] Failed to notify close UI:', err);
        });
    }

    // =============================================================
    // تحديث موضع الإشعارات
    // =============================================================
    function setNotificationPosition(position) {
        if (!notificationsContainer) return;

        notificationsContainer.className = 'notifications-container';

        switch (position) {
            case 'right':
                notificationsContainer.classList.add('position-right');
                break;
            case 'center':
                notificationsContainer.classList.add('position-center');
                break;
            case 'bottom':
                notificationsContainer.classList.add('position-bottom');
                break;
            case 'left':
            default:
                // الموقع الافتراضي
                break;
        }
    }

    // =============================================================
    // معالجة الرسائل من FiveM
    // =============================================================
    window.addEventListener('message', function(event) {
        const data = event.data;

        if (!data || !data.action) return;

        switch (data.action) {
            case 'showNotification':
                showNotification(data.data || data);
                break;

            case 'removeNotification':
                removeNotification(data.id);
                break;

            case 'clearAll':
                removeAllNotifications();
                break;

            case 'showCritical':
                showCritical(data.data || data);
                break;

            case 'hideCritical':
                hideCritical();
                break;

            case 'openUI':
                openUI();
                break;

            case 'closeUI':
                closeUI();
                break;

            case 'hideUI':
                document.body.style.visibility = 'hidden';
                break;

            case 'showUI':
                document.body.style.visibility = 'visible';
                break;

            case 'setPosition':
                setNotificationPosition(data.position);
                break;

            case 'playSound':
                if (window.OxSecureSounds) {
                    window.OxSecureSounds.play(data.soundName || 'default');
                }
                break;

            case 'updateData':
                // معالجة تحديث البيانات (للتطوير المستقبلي)
                break;

            default:
                console.log('[ox_lib_secure] Unknown action:', data.action);
        }
    });

    // =============================================================
    // أحداث الأزرار
    // =============================================================
    function setupEventListeners() {
        // إصلاح: التحقق من وجود العناصر قبل إضافة المستمعين
        if (criticalCloseBtn) {
            criticalCloseBtn.addEventListener('click', function() {
                hideCritical();
            });
        }

        const uiCloseBtn = document.getElementById('ui-close');
        if (uiCloseBtn) {
            uiCloseBtn.addEventListener('click', function() {
                closeUI();
            });
        }
    }

    // =============================================================
    // معالجة مفتاح Escape لإغلاق الواجهة
    // =============================================================
    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
            closeUI();
            hideCritical();
        }
    });

    // =============================================================
    // التهيئة عند تحميل الصفحة
    // =============================================================
    function initialize() {
        ensureDOMElements();
        setupEventListeners();
        uiReady = true;
        notifyUIReady();
        console.log('[ox_lib_secure] NUI initialized and ready.');
    }

    document.addEventListener('DOMContentLoaded', initialize);

    // في حالة كان الصفحة محملة بالفعل
    if (document.readyState === 'complete' || document.readyState === 'interactive') {
        initialize();
    }

})();
