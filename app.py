from flask import Flask, request, jsonify
from flask_cors import CORS
import logging
import os
from openai import OpenAI

app = Flask(__name__)

# Enable CORS for your specific frontend domain
CORS(app, resources={r"/*": {"origins": ["https://rferns-0009.xyz"]}})

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

client = OpenAI(
    api_key=os.environ.get("OPENAI_API_KEY", ""),
    http_client=None # Forces the SDK to ignore the broken internal httpx proxy logic
)

def generate_response(user_input: str) -> str:
    system_prompt = (
        "You are a professional assistant strictly specializing in SaaS, Cloud Computing, and IT frameworks. "
        "First, evaluate if the user's request is related to these domains. "
        "If the request is NOT related to IT, Cloud, or SaaS (e.g., general chat, cooking, personal advice), "
        "you must refuse to answer and reply EXACTLY with this message:\n\n"
        "⚠️ This assistant specializes in **SaaS, Cloud Computing, and IT frameworks**.\n\n"
        "Please ask about topics like SaaS platforms, IT methodologies, cloud services, "
        "automation, DevOps, project management, or architecture best practices.\n\n"
        "If the request IS related to your specialty, respond in **Markdown** with the following structure:\n"
        "1. **Overview** – one or two clear paragraphs\n"
        "2. **Key Points** – concise bulleted list of highlights\n"
        "3. **Code (if relevant)** – runnable examples in fenced Markdown blocks\n"
        "4. **References** – links to official documentation or trusted sources"
    )
    
    user_prompt = f"User request: {user_input}"
    
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt}
        ],
        temperature=0.2, # Lower temperature makes the model adhere strictly to the rules
        max_tokens=800
    )
    return response.choices[0].message.content.strip()

@app.route("/chat", methods=["POST"])
def chatbot():
    try:
        data = request.get_json(force=True)
        user_input = data.get("user_input", "")
        
        if not user_input:
            return jsonify({"error": "Missing user_input"}), 400
        
        # We simply pass the input to the LLM, and it decides whether to answer or reject
        bot_response = generate_response(user_input)
            
        logger.info("Bot response generated")
        return jsonify({"response": bot_response})
        
    except Exception as e:
        logger.exception("Internal server error")
        return jsonify({"error": "Internal server error", "details": str(e)}), 500

@app.route("/", methods=["GET"])
def root():
    return jsonify({"status": "ok"})