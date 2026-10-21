// the effect's own translations, see po/: KWin's QML engine gives scripts KLocalizedString's i18n functions, but with
// KWin's domain, so the effect names its own; imported without .pragma library, so that it sees them
const domain = "karousel_overview";

function tr(text, ...args) {
    return i18nd(domain, text, ...args);
}

// with a context that tells translators where the text shows
function trc(context, text, ...args) {
    return i18ndc(domain, context, text, ...args);
}
