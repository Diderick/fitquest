const validDate = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
  && Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
export function validProfileNutrition(key, value) {
  if (key === 'profile_gender') return value === null || ['male', 'female', 'other'].includes(value);
  if (key === 'profile_photo_v1') {
    if (value === null) return true;
    if (typeof value !== 'string' || value.length > 409600 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) return false;
    const data = Buffer.from(value, 'base64');
    return data.length >= 33 && data.length <= 300 * 1024 && data.toString('base64') === value
      && data.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
      && data.subarray(12, 16).toString() === 'IHDR'
      && data.readUInt32BE(16) > 0 && data.readUInt32BE(16) <= 256
      && data.readUInt32BE(20) > 0 && data.readUInt32BE(20) <= 256;
  }
  if (key.startsWith('nutrition_goal.')) return validDate(key.slice(15)) && Number.isInteger(value) && value > 0 && value <= 100000;
  if (key === 'nutrition_goal_kcal') return Number.isInteger(value) && value > 0 && value <= 100000;
  if (key.startsWith('nutrition_entry.')) {
    if (value === null) return true;
    if (typeof value !== 'string' || value.length > 4000) return false;
    let entry;
    try { entry = JSON.parse(value); } catch { return false; }
    if (!entry || typeof entry !== 'object') return false;
    return entry && typeof entry.id === 'string' && /^[\w-]{1,80}$/.test(entry.id) && key === `nutrition_entry.${entry.id}`
      && ['food', 'drink'].includes(entry.kind) && typeof entry.name === 'string' && entry.name.trim().length > 0 && entry.name.length <= 120
      && typeof entry.portion === 'string' && entry.portion.length <= 120
      && Number.isInteger(entry.calories) && entry.calories >= 0 && entry.calories <= 100000
      && typeof entry.legacy === 'boolean'
      && ((validDate(entry.date) && typeof entry.time === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(entry.time))
        || (entry.legacy && entry.date === null && entry.time === null));
  }
  return undefined;
}
