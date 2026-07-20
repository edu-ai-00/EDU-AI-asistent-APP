# AI System Information Sheet

*Effective from: 20 May 2026 · Version: 1.0 (preliminary)*

> **Note:** The final wording will be supplied by the Provider. The content below is based on Regulation (EU) **2024/1689** ("AI Act"), in particular Art. 13 (transparency), Art. 14 (human oversight), Art. 50 (transparency duties), Art. 52 (GPAI providers), and the Provider's internal AI policy. In case of discrepancy with the [Czech original](/ai), the Czech version prevails.

## 1. Purpose and AI system classification

1.1 The EDU AI assistant Application integrates AI-based features to provide educational support (explanations, recommendations, answers, adaptive difficulty, contextual hints).

1.2 **AI Act classification:** AI features are designed and operated as an AI system within Art. 3(1) AI Act. Given that:

- the target audience is pupils and students,
- some users are children (vulnerable group, Art. 5(1)(b) AI Act),
- AI is used in an **educational context**,

the Provider maintains the **highest level of care**, transparency and human oversight. The Application **does not use** AI features listed in Annex III AI Act (high-risk AI in education); in particular it:

- does not use AI for **binding evaluation** of study results or admission/progression/termination decisions,
- does not use AI for **behaviour monitoring** or exam-cheating detection,
- does not use AI for **biometric identification** or **emotion detection**.

## 2. AI models used

2.1 The Application uses commercial LLMs operated by reputable EU-based providers:

| Provider | Models | Purpose in Application | Processing location |
|---|---|---|---|
| OpenAI Ireland Ltd. | GPT-4o, GPT-4o mini, GPT-4.1 (and successors) | AI chat assistant, lesson explanations, quiz feedback | EU (Ireland); USA via EU–U.S. DPF |
| Anthropic Ireland Ltd. | Claude Sonnet, Claude Haiku (and successors) | AI chat assistant, in-depth explanations, alternative explanations | EU (Ireland); USA via EU–U.S. DPF |
| OpenRouter, Inc. | Routing proxy (optional) | Query routing and load balancing | USA; SCC |

2.2 **Inputs are not used for model training** — agreements with AI providers prohibit training on Application data (Zero Data Retention / training opt-out).

2.3 OpenAI and Anthropic models are **general-purpose AI models (GPAI)** under Art. 51+ AI Act. These providers must publish technical documentation, training-data summaries and ensure copyright compliance.

## 3. AI features in the Application

### 3.1 AI mentor (Chat)

Conversational AI assistant in Chat. Answers educational questions, explains concepts, suggests study approaches. Clearly labelled per Art. 50 AI Act.

### 3.2 Quiz answer explanations

After completing a quiz, AI may generate in-depth explanation, alternative approach or example. AI outputs are marked.

### 3.3 Adaptive difficulty (FSRS)

The Free Spaced Repetition Scheduler adapts card-repetition frequency to individual memory curve. Not generative AI — statistical model.

### 3.4 Next-content recommendation

Based on completed lessons and quizzes. Deterministic rule-based logic, not neural network.

## 4. Inputs, outputs and data processing

4.1 **Inputs:**

- user prompt (for chat),
- lesson/quiz context (for explanations),
- Provider's system prompt (instructions, safety filters, persona).

4.2 **Outputs:** textual or structured (JSON).

4.3 **Processing:**

- Inputs sent over TLS 1.3.
- Inputs/outputs retained max **90 days** for security, debugging, QA, then anonymised or deleted.
- Users reminded not to enter sensitive personal data (Terms 7.6).

## 5. Human oversight (Art. 14 AI Act)

5.1 Human oversight ensured by:

- Development team reviews AI output samples and refines system prompts.
- "Report" button next to each AI response.
- Pedagogical team evaluates error statistics and iterates content.
- Right to **human review** of any AI evaluation significantly affecting the user at [app@edu-ai.eu](mailto:app@edu-ai.eu). Handled within 30 days.

5.2 **AI does not replace teachers.** Pedagogical decisions always made by teacher or educational institution.

## 6. Limitations and risks

6.1 AI may generate **inaccurate, incomplete, outdated or inappropriate responses** ("hallucinations"). Inherent to LLMs.

6.2 Specific limitations:

- **Factual accuracy:** errors possible on niche/current topics. Training cut-off varies by model.
- **Mathematics and logic:** errors in intermediate steps possible.
- **Language:** optimised for Czech and English; quality may be lower in other languages.
- **Pedagogical suitability:** AI adapts to user age but may rarely provide unsuitable content.
- **Bias:** AI models may exhibit training-data bias; we mitigate known biases.

6.3 **The user shall always verify AI outputs appropriately**, especially for study, school submissions, evaluation (Terms 7.5).

## 7. Safeguards for children and vulnerable users

7.1 Per Art. 5(1)(b) AI Act (no exploitation of children) and Art. 5(1)(a) (no manipulative techniques):

- AI mentor uses **age-appropriate language** and tone.
- AI **does not use manipulative techniques** or persuasive design to increase time spent.
- AI is instructed to **refuse answers** on unsuitable topics (violence, self-harm, sexually explicit content, illegal acts) and recommend contacting an adult or professional.
- AI is instructed to **recommend a crisis hotline** (e.g., [Linka bezpečí 116 111](https://www.linkabezpeci.cz) in CZ, 116 123 EU-wide) on mental-distress indicators.
- In school mode, the educational institution can **fully disable** AI features.
- Full AI access only for users **15+** (Terms section 4).

## 8. User rights relating to AI

8.1 **Right to transparency** (Art. 50 AI Act): AI outputs clearly marked as AI-generated.

8.2 **Right to disable AI**: anytime in App Settings. Full use without AI possible.

8.3 **Right to human review** (Art. 14 AI Act): at [app@edu-ai.eu](mailto:app@edu-ai.eu).

8.4 **Right to report inappropriate output**: via "Report" button or [app@edu-ai.eu](mailto:app@edu-ai.eu).

8.5 **Right to delete inputs**: see [Privacy Policy](/privacy/en).

## 9. Changes to this sheet

9.1 Updated on changes to AI models, features or regulation. Current version at [app.edu-ai.eu/ai](https://app.edu-ai.eu/ai).

9.2 Material changes notified at least 30 days in advance.

## 10. Contact

Questions: [app@edu-ai.eu](mailto:app@edu-ai.eu).
Human review of AI evaluation: [app@edu-ai.eu](mailto:app@edu-ai.eu) (subject "Human review of AI").
AI personal-data questions: [gdpr@edu-ai.eu](mailto:gdpr@edu-ai.eu).
