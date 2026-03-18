from flask import Flask, request, jsonify
from flask_cors import CORS
import logging
import os
from openai import OpenAI

app = Flask(__name__)

# 2. Enable CORS for your specific frontend domain
# This allows your S3/CloudFront frontend to securely talk to your EKS backend.
CORS(app, resources={r"/*": {"origins": ["https://rferns-0009.xyz"]}})

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

client = OpenAI(
    api_key=os.environ.get("OPENAI_API_KEY",""),
    http_client=None # Forces the SDK to ignore the broken internal httpx proxy logic
)

def is_saas_or_it_related(user_input: str) -> bool:
    keywords = [
        "saas", "cloud", "it", "framework", "agile", "scrum",
        "devops", "itil", "six sigma", "project management",
        "kubernetes", "docker", "microservices", "aws", "azure",
        "gcp", "terraform", "ansible", "automation", "compliance",
        "governance", "architecture", "design pattern"
    ]
    return any(kw in user_input.lower() for kw in keywords)

def generate_response(user_input: str) -> str:
    system_prompt = (
        "You are a professional assistant for SaaS, Cloud, and IT frameworks. "
        "Always respond in **Markdown** with the following structure:\n\n"
        "1. **Overview** – one or two clear paragraphs\n"
        "2. **Key Points** – concise bulleted list of highlights\n"
        "3. **Code (if relevant)** – runnable examples in fenced Markdown blocks\n"
        "4. **References** – links to official documentation or trusted sources\n"
    )
    user_prompt = f"User request: {user_input}"
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role":"system", "content": system_prompt},
            {"role":"user", "content": user_prompt}
        ],
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
        if not is_saas_or_it_related(user_input):
            bot_response = (
                "⚠️ This assistant specializes in **SaaS, Cloud Computing, and IT frameworks**.\n\n"
                "Please ask about topics like SaaS platforms, IT methodologies, cloud services, "
                "automation, DevOps, project management, or architecture best practices."
            )
        else:
            bot_response = generate_response(user_input)
        logger.info("Bot response generated")
        return jsonify({"response": bot_response})
    except Exception as e:
        logger.exception("Internal server error")
        return jsonify({"error":"Internal server error", "details": str(e)}), 500

@app.route("/", methods=["GET"])
def root():
    return jsonify({"status":"ok"})