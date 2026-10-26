/**
 * The few words the calendar and dropdown draw themselves (they are plain DOM, outside Angular's templates), in the language the app
 * is in. The app keeps <html lang> up to date (I18nService), so these read it when they open.
 */
const WORDS = {
  sw: {
    months: ['Januari', 'Februari', 'Machi', 'Aprili', 'Mei', 'Juni', 'Julai', 'Agosti', 'Septemba', 'Oktoba', 'Novemba', 'Desemba'],
    week: ['Jt', 'Jn', 'Jt', 'Alh', 'Ij', 'Jm', 'Jp'],
    today: 'Leo',
    clear: 'Futa',
    selectDate: 'Chagua tarehe',
    select: 'Chagua…',
    locale: 'sw-TZ',
  },
  en: {
    months: ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
    week: ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'],
    today: 'Today',
    clear: 'Clear',
    selectDate: 'Select date',
    select: 'Select…',
    locale: 'en-GB',
  },
};

export function uiText() {
  const lang = typeof document !== 'undefined' && document.documentElement.lang === 'en' ? 'en' : 'sw';
  return WORDS[lang];
}
