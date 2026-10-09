const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

admin.initializeApp();

exports.deleteMyAccount = onCall(
  { region: 'us-central1', enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before deleting your account.');
    }

    const uid = request.auth.uid;
    const authTime = Number(request.auth.token.auth_time || 0);
    const nowSeconds = Math.floor(Date.now() / 1000);
    if (!authTime || nowSeconds - authTime > 300) {
      throw new HttpsError(
        'failed-precondition',
        'For security, sign in again and retry account deletion within five minutes.',
      );
    }

    try {
      const userDocument = admin.firestore().collection('users').doc(uid);
      await admin.firestore().recursiveDelete(userDocument);

      const bucket = admin.storage().bucket();
      await bucket.deleteFiles({ prefix: `users/${uid}/` });

      await admin.auth().deleteUser(uid);
      return { deleted: true };
    } catch (error) {
      console.error('Account deletion failed', { uid, message: error.message });
      throw new HttpsError(
        'internal',
        'Account deletion could not be completed. No success was reported; contact support before retrying.',
      );
    }
  },
);
