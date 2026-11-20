(() => {
    const interactive = "a, button, input, textarea, select, summary, label, audio, video, [onclick], [contenteditable]";
    const editable = "input, textarea, select, [contenteditable]";
    const post = value => window.webkit.messageHandlers.hayakiReviewerInput.postMessage(value);
    let touchStart = null;
    document.body.classList.add("reviewer-input");

    const canUseGesture = event => event.isTrusted
        && event.target instanceof Element
        && !event.target.closest(interactive)
        && !String(window.getSelection());

    document.addEventListener("click", event => {
        if (canUseGesture(event)) {
            post({ tapX: event.clientX / window.innerWidth, tapY: event.clientY / window.innerHeight });
        }
    }, { passive: true });

    document.addEventListener("touchstart", event => {
        if (!canUseGesture(event)) {
            touchStart = null;
            return;
        }
        const { clientX, clientY } = event.touches[0];
        touchStart = { clientX, clientY, time: event.timeStamp, count: event.touches.length, target: event.target };
    }, { passive: true });

    document.addEventListener("touchcancel", () => { touchStart = null; }, { passive: true });

    document.addEventListener("touchend", event => {
        if (event.touches.length > 0) return;
        if (!touchStart) return;
        const start = touchStart;
        touchStart = null;
        if (!canUseGesture(event)) return;
        const { clientX, clientY } = event.changedTouches[0];
        const dx = clientX - start.clientX;
        const dy = clientY - start.clientY;
        const distance = Math.hypot(dx, dy);
        const time = Math.max(event.timeStamp - start.time, 1);
        if (start.count > 1) {
            if (distance < 22 && time < 350 && start.count <= 4) post({ fingers: start.count });
            return;
        }
        if (distance < 20) return;

        const horizontal = Math.abs(dx) > Math.abs(dy);
        // Leave scrollable media, template regions and an oversized card to WebKit.
        for (let node = start.target; node; node = node.parentElement) {
            const style = getComputedStyle(node);
            const overflow = horizontal ? style.overflowX : style.overflowY;
            const range = horizontal ? node.scrollWidth - node.clientWidth : node.scrollHeight - node.clientHeight;
            if (range > 2 && (node === document.scrollingElement || overflow === "auto" || overflow === "scroll")) return;
        }
        post({ dx, dy, time });
    }, { passive: true });

    // Tell the reviewer while a text field has focus, so keys that type text
    // (Space, Return, digits, letters) reach the field instead of the
    // reviewer's keyboard shortcuts.
    // The reviewer clears its copy when the card changes, since a removed
    // field does not report losing focus, so every change is posted.
    const reportEditing = () => {
        const active = document.activeElement;
        post({ editing: active instanceof Element && active !== document.body && !!active.closest(editable) });
    };
    document.addEventListener("focusin", reportEditing, true);
    document.addEventListener("focusout", () => setTimeout(reportEditing, 0), true);

    window.hayakiReviewerKeys = [];
    document.addEventListener("keydown", event => {
        if (!event.isTrusted || event.repeat || event.isComposing || event.defaultPrevented
            || (event.target instanceof Element && event.target.closest(editable))) return;
        const key = event.key === " " ? "space" : event.key === "Enter" ? "return" : event.key.toLowerCase();
        const modifiers = [];
        if (event.metaKey) modifiers.push("command");
        if (event.ctrlKey) modifiers.push("control");
        if (event.altKey) modifiers.push("option");
        if (event.shiftKey) modifiers.push("shift");
        const signature = [key, ...modifiers].join("+");
        if (!window.hayakiReviewerKeys.includes(signature)) return;
        event.preventDefault();
        post({ key, modifiers });
    });
})();
