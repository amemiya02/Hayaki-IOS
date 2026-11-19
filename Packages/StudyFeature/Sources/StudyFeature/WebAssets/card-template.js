/*
 * Hayaki bridge for AnkiDroid's public template scripting API 0.0.3.
 * Method names adapted from AnkiDroid's scripts/js-api.js.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
(() => {
    "use strict";

    const jsApiList = {
        ankiGetNewCardCount: "newCardCount",
        ankiGetLrnCardCount: "lrnCardCount",
        ankiGetRevCardCount: "revCardCount",
        ankiGetETA: "eta",
        ankiGetCardMark: "cardMark",
        ankiGetCardFlag: "cardFlag",
        ankiGetNextTime1: "nextTime1",
        ankiGetNextTime2: "nextTime2",
        ankiGetNextTime3: "nextTime3",
        ankiGetNextTime4: "nextTime4",
        ankiGetCardReps: "cardReps",
        ankiGetCardInterval: "cardInterval",
        ankiGetCardFactor: "cardFactor",
        ankiGetCardMod: "cardMod",
        ankiGetCardId: "cardId",
        ankiGetCardNid: "cardNid",
        ankiGetCardType: "cardType",
        ankiGetCardDid: "cardDid",
        ankiGetCardLeft: "cardLeft",
        ankiGetCardODid: "cardODid",
        ankiGetCardODue: "cardODue",
        ankiGetCardQueue: "cardQueue",
        ankiGetCardLapses: "cardLapses",
        ankiGetCardDue: "cardDue",
        ankiIsInFullscreen: "isInFullscreen",
        ankiSetFullscreenButtonsAndMenu: "setFullscreenButtonsAndMenu",
        ankiSetFullscreenButtonsOnly: "setFullscreenButtonsOnly",
        ankiSetFullscreenAllGone: "setFullscreenAllGone",
        ankiIsTopbarShown: "isTopbarShown",
        ankiIsInNightMode: "isInNightMode",
        ankiIsDisplayingAnswer: "isDisplayingAnswer",
        ankiGetDeckName: "deckName",
        ankiIsActiveNetworkMetered: "isActiveNetworkMetered",
        ankiTtsFieldModifierIsAvailable: "ttsFieldModifierIsAvailable",
        ankiTtsIsSpeaking: "ttsIsSpeaking",
        ankiTtsStop: "ttsStop",
        ankiBuryCard: "buryCard",
        ankiBuryNote: "buryNote",
        ankiSuspendCard: "suspendCard",
        ankiSuspendNote: "suspendNote",
        ankiAddTagToCard: "addTagToCard",
        ankiResetProgress: "resetProgress",
        ankiMarkCard: "markCard",
        ankiToggleFlag: "toggleFlag",
        ankiSearchCard: "searchCard",
        ankiSearchCardWithCallback: "searchCardWithCallback",
        ankiTtsSpeak: "ttsSpeak",
        ankiTtsSetLanguage: "ttsSetLanguage",
        ankiTtsSetPitch: "ttsSetPitch",
        ankiTtsSetSpeechRate: "ttsSetSpeechRate",
        ankiEnableHorizontalScrollbar: "enableHorizontalScrollbar",
        ankiEnableVerticalScrollbar: "enableVerticalScrollbar",
        ankiSetCardDue: "setCardDue",
        ankiShowNavigationDrawer: "showNavigationDrawer",
        ankiShowOptionsMenu: "showOptionsMenu",
        ankiShowToast: "showToast",
        ankiShowAnswer: "showAnswer",
        ankiAnswerEase1: "answerEase1",
        ankiAnswerEase2: "answerEase2",
        ankiAnswerEase3: "answerEase3",
        ankiAnswerEase4: "answerEase4",
        ankiSttSetLanguage: "sttSetLanguage",
        ankiSttStart: "sttStart",
        ankiSttStop: "sttStop",
        ankiAddTagToNote: "addTagToNote",
        ankiSetNoteTags: "setNoteTags",
        ankiGetNoteTags: "getNoteTags",
    };

    let generation = "";
    const hooks = new Map();

    function begin(token) {
        generation = token;
        hooks.clear();
    }

    function send(token, command, version, developer, data) {
        const handler = window.webkit?.messageHandlers?.hayakiTemplate;
        if (!handler) return Promise.resolve({ success: false, value: -1 });
        return handler.postMessage({
            token, command, version, developer,
            data: data == null ? "" : typeof data === "object" ? JSON.stringify(data) : String(data)
        });
    }

    class AnkiDroidJS {
        #generation;

        constructor({ developer, version }) {
            this.developer = developer;
            this.version = version;
            this.#generation = generation;
            this.handleRequest("init").catch(console.error);
        }

        static init(options) { return new AnkiDroidJS(options); }

        async handleRequest(command, data) {
            const result = await send(this.#generation, command, this.version, this.developer, data);
            // The Android helper returns the raw response for interval and deck-name calls.
            if (command.startsWith("nextTime") || command === "deckName") return JSON.stringify(result);
            return result;
        }
    }

    for (const [name, command] of Object.entries(jsApiList)) {
        AnkiDroidJS.prototype[name] = function (value, detail) {
            switch (command) {
            case "ttsSpeak": return this.handleRequest(command, { text: value, queueMode: detail ?? 0 });
            case "showToast": return this.handleRequest(command, { text: value, shortLength: detail ?? true });
            case "addTagToNote": return this.handleRequest(command, { noteId: value, tag: detail });
            case "setNoteTags": {
                const tags = value.map(tag => tag.trim().replace(/[\s\u3000]/gu, "_"));
                return this.handleRequest(command, { tags });
            }
            default: return this.handleRequest(command, value);
            }
        };
    }

    function legacy(command) {
        return send(generation, command, "0.0.3", "Hayaki").catch(console.error);
    }

    window.AnkiDroidJS = AnkiDroidJS;
    window.showAnswer = () => legacy("showAnswer");
    window.reloadPage = () => legacy("reloadPage");
    window.taFocus = () => document.querySelector("input#typeans")?.focus();
    for (let rating = 1; rating <= 4; rating++) {
        window["buttonAnswerEase" + rating] = () => legacy("answerEase" + rating);
    }

    window.addHook = (name, callback) => {
        if ((name === "ankiSearchCard" || name === "ankiSttResult") && typeof callback === "function") {
            const callbacks = hooks.get(name) ?? [];
            callbacks.push(callback);
            hooks.set(name, callbacks);
        }
    };
    function emit(token, name, result) {
        if (token !== generation) return;
        for (const callback of hooks.get(name) ?? []) callback(result);
    }
    window.hayakiTemplate = { begin, emit };
})();
