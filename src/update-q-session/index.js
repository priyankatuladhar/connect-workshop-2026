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
 *   event.Details.Parameters.patientId
 *   event.Details.Parameters.firstName
 *   event.Details.Parameters.lastName
 *   event.Details.Parameters.patientFound
 */

const {
  ConnectWisdomService,
} = require('@aws-sdk/client-wisdom');

const wisdom = new ConnectWisdomService({ region: process.env.AWS_REGION });

const CONNECT_INSTANCE_ID = process.env.CONNECT_INSTANCE_ID;
const AI_ASSISTANT_ID = process.env.AI_ASSISTANT_ID;

exports.handler = async (event) => {
  try {
    const contactId = event?.Details?.ContactData?.ContactId;
    const params = event?.Details?.Parameters || {};

    if (!contactId) {
      console.error('update_q_session: missing ContactId in event');
      return { result: 'error', reason: 'missing_contact_id' };
    }

    if (!CONNECT_INSTANCE_ID || !AI_ASSISTANT_ID) {
      console.error('update_q_session: CONNECT_INSTANCE_ID or AI_ASSISTANT_ID not set');
      return { result: 'error', reason: 'missing_env_vars' };
    }

    // Build session data — only include non-empty values
    const sessionData = {};
    if (params.patientId) sessionData.patientId = params.patientId;
    if (params.firstName) sessionData.firstName = params.firstName;
    if (params.lastName) sessionData.lastName = params.lastName;
    sessionData.patientFound = params.patientFound || 'false';
    sessionData.verificationStatus = 'unverified';

    // Find the active Wisdom session for this contact
    const sessions = await wisdom.listSessions({
      assistantId: AI_ASSISTANT_ID,
    });

    // Sessions are keyed by contact ID — find the one for this call
    const matchingSession = (sessions.sessionSummaries || []).find(
      (s) => s.sessionData?.contactId === contactId || s.name === contactId
    );

    if (!matchingSession) {
      console.log(`update_q_session: no session found for contact ${contactId} — will be created by Q in Connect on first turn`);
      return { result: 'no_session_yet', contactId };
    }

    await wisdom.updateSessionData({
      assistantId: AI_ASSISTANT_ID,
      sessionId: matchingSession.sessionId,
      data: Object.entries(sessionData).map(([key, value]) => ({
        key,
        value: { stringValue: String(value) },
      })),
    });

    console.log(`update_q_session: session updated for contact ${contactId}, patient ${params.patientId}`);
    return { result: 'success', contactId, patientId: params.patientId || 'unknown' };

  } catch (err) {
    console.error('update_q_session error:', err.message);
    // Return gracefully — a failed session update should not block the call
    return { result: 'error', reason: err.message };
  }
};
