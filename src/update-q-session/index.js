/**
 * update-q-session — Contact Flow Lambda (Node.js 18.x)
 *
 * Invoked directly by the Contact Flow after customer-lookup.
 * Pushes verified patient data into the Q in Connect (Wisdom) session
 * so the AI assistant can personalise responses without re-asking.
 *
 * Required env vars (set in Step 13 of the deployment guide):
 *   CONNECT_INSTANCE_ID  — Amazon Connect instance ID (UUID)
 *   AI_ASSISTANT_ID      — Q in Connect assistant ID (UUID)
 *
 * Event shape from Contact Flow:
 *   event.Details.ContactData.ContactId
 *   event.Details.ContactData.CustomerEndpoint.Address   (the caller ANI — read automatically)
 *   event.Details.Parameters.sessionArn          (RECOMMENDED — set to $.Wisdom.SessionArn)
 *   event.Details.Parameters.patientId
 *   event.Details.Parameters.firstName
 *   event.Details.Parameters.lastName
 *   event.Details.Parameters.patientFound
 *   event.Details.Parameters.phoneNumber         (optional — overrides the ANI)
 *   event.Details.Parameters.preferredLanguage   (optional, defaults to "en")
 *   event.Details.Parameters.verificationStatus  (optional, defaults to "unverified")
 */

const {
  QConnectClient,
  SearchSessionsCommand,
  UpdateSessionDataCommand,
} = require('@aws-sdk/client-qconnect');

const wisdom = new QConnectClient({ region: process.env.AWS_REGION });

const CONNECT_INSTANCE_ID = process.env.CONNECT_INSTANCE_ID;
const AI_ASSISTANT_ID = process.env.AI_ASSISTANT_ID;

exports.handler = async (event) => {
  try {
    const contactId = event?.Details?.ContactData?.ContactId;
    const params = event?.Details?.Parameters || {};
    // Caller's number (ANI) is always in ContactData on a voice call — use it so
    // the AI can register a new patient without asking for the phone number.
    const ani = event?.Details?.ContactData?.CustomerEndpoint?.Address || '';

    if (!contactId) {
      console.error('update_q_session: missing ContactId in event');
      return { result: 'error', reason: 'missing_contact_id' };
    }

    if (!CONNECT_INSTANCE_ID || !AI_ASSISTANT_ID) {
      console.error('update_q_session: CONNECT_INSTANCE_ID or AI_ASSISTANT_ID not set');
      return { result: 'error', reason: 'missing_env_vars' };
    }

    // Build session data — only include non-empty values.
    // NOTE: the AI Agent system prompt reads {{$.Custom.patientName}} and
    // {{$.Custom.preferredLanguage}} — they must be pushed here or the
    // personalised greeting resolves to an empty string.
    const sessionData = {};
    if (params.patientId) sessionData.patientId = params.patientId;
    if (params.firstName) sessionData.firstName = params.firstName;
    if (params.lastName) sessionData.lastName = params.lastName;

    const patientName = [params.firstName, params.lastName]
      .filter(Boolean)
      .join(' ')
      .trim();
    if (patientName) sessionData.patientName = patientName;

    const phoneNumber = params.phoneNumber || ani;
    if (phoneNumber) sessionData.phoneNumber = phoneNumber;

    sessionData.preferredLanguage = params.preferredLanguage || 'en';
    sessionData.patientFound = params.patientFound || 'false';
    sessionData.verificationStatus = params.verificationStatus || 'unverified';

    // Preferred: the Contact Flow passes the session ARN it just created, as the
    // "sessionArn" parameter set to $.Wisdom.SessionArn. Fall back to searching
    // by contact id (older flows). UpdateSessionData accepts the ARN or the id.
    let sessionId = params.sessionArn || params.sessionId || '';

    if (!sessionId) {
      try {
        const sessions = await wisdom.send(new SearchSessionsCommand({
          assistantId: AI_ASSISTANT_ID,
          searchExpression: {
            filters: [{ field: 'NAME', operator: 'EQUALS', value: contactId }],
          },
        }));
        const match = (sessions.sessionSummaries || []).find((s) => s.name === contactId);
        sessionId = (match && match.sessionId) || '';
      } catch (searchErr) {
        console.log(`update_q_session: session search failed (${searchErr.message})`);
      }
    }

    if (!sessionId) {
      console.log(`update_q_session: no session for contact ${contactId} — pass the "sessionArn" parameter as $.Wisdom.SessionArn from the flow`);
      return { result: 'no_session_yet', contactId };
    }

    await wisdom.send(new UpdateSessionDataCommand({
      assistantId: AI_ASSISTANT_ID,
      sessionId,
      data: Object.entries(sessionData).map(([key, value]) => ({
        key,
        value: { stringValue: String(value) },
      })),
    }));

    console.log('update_q_session: session %s updated with %j', sessionId, sessionData);
    return { result: 'success', contactId, sessionId, patientId: params.patientId || 'unknown' };

  } catch (err) {
    console.error('update_q_session error:', err.message);
    // Return gracefully — a failed session update should not block the call
    return { result: 'error', reason: err.message };
  }
};
