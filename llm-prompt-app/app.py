from flask import Flask, request, render_template_string, jsonify
import requests
import json
import os

app = Flask(__name__)

# Get Ollama URL from environment or use default
OLLAMA_URL = os.environ.get('OLLAMA_URL', 'http://ollama.ollama.svc.cluster.local:11434')

HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>LLM Prompt Interface</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            max-width: 800px;
            width: 100%;
            padding: 40px;
        }
        h1 {
            color: #667eea;
            margin-bottom: 10px;
            font-size: 2.5em;
        }
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            font-size: 1.1em;
        }
        .form-group {
            margin-bottom: 20px;
        }
        label {
            display: block;
            margin-bottom: 8px;
            color: #333;
            font-weight: 600;
        }
        input[type="text"], textarea {
            width: 100%;
            padding: 12px;
            border: 2px solid #e0e0e0;
            border-radius: 10px;
            font-size: 16px;
            transition: border-color 0.3s;
        }
        input[type="text"]:focus, textarea:focus {
            outline: none;
            border-color: #667eea;
        }
        textarea {
            resize: vertical;
            min-height: 120px;
            font-family: inherit;
        }
        button {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 15px 40px;
            border-radius: 10px;
            font-size: 18px;
            font-weight: 600;
            cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
            width: 100%;
        }
        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 20px rgba(102, 126, 234, 0.4);
        }
        button:active {
            transform: translateY(0);
        }
        button:disabled {
            background: #ccc;
            cursor: not-allowed;
            transform: none;
        }
        .response-section {
            margin-top: 30px;
        }
        .response-box {
            background: #f8f9fa;
            border-left: 4px solid #667eea;
            padding: 20px;
            border-radius: 10px;
            max-height: 400px;
            overflow-y: auto;
        }
        .response-box pre {
            white-space: pre-wrap;
            word-wrap: break-word;
            font-family: 'Courier New', monospace;
            color: #333;
            line-height: 1.6;
        }
        .loading {
            text-align: center;
            color: #667eea;
            font-size: 1.1em;
            padding: 20px;
        }
        .error {
            color: #dc3545;
            background: #f8d7da;
            border-left-color: #dc3545;
        }
        .info {
            background: #d1ecf1;
            border: 1px solid #bee5eb;
            border-radius: 10px;
            padding: 15px;
            margin-bottom: 20px;
            color: #0c5460;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🤖 LLM Prompt Interface</h1>
        <p class="subtitle">Powered by Ollama and Kubernetes</p>
        
        <div class="info">
            <strong>Connected to:</strong> {{ ollama_url }}<br>
            <strong>Model:</strong> tinyllama
        </div>
        
        <form method="post" id="promptForm">
            <div class="form-group">
                <label for="prompt">Enter your prompt:</label>
                <textarea 
                    name="prompt" 
                    id="prompt" 
                    placeholder="Ask me anything..."
                    required
                >{{ last_prompt }}</textarea>
            </div>
            <button type="submit" id="submitBtn">Send Prompt</button>
        </form>
        
        {% if response %}
        <div class="response-section">
            <h3>Response:</h3>
            <div class="response-box {% if error %}error{% endif %}">
                <pre>{{ response }}</pre>
            </div>
        </div>
        {% endif %}
    </div>
    
    <script>
        const form = document.getElementById('promptForm');
        const submitBtn = document.getElementById('submitBtn');
        
        form.addEventListener('submit', function() {
            submitBtn.disabled = true;
            submitBtn.textContent = 'Processing...';
        });
    </script>
</body>
</html>
"""

def query_ollama(prompt):
    """Query Ollama API with streaming support"""
    url = f"{OLLAMA_URL}/api/generate"
    payload = {
        "model": "tinyllama",
        "prompt": prompt,
        "stream": False
    }
    
    try:
        response = requests.post(url, json=payload, timeout=120)
        response.raise_for_status()
        
        # Parse response
        result = response.json()
        return result.get("response", "No response received")
        
    except requests.exceptions.ConnectionError:
        return f"Error: Cannot connect to Ollama at {OLLAMA_URL}. Please ensure Ollama is running."
    except requests.exceptions.Timeout:
        return "Error: Request timed out. The model might be loading or the prompt is too complex."
    except requests.exceptions.RequestException as e:
        return f"Error: {str(e)}"
    except json.JSONDecodeError:
        return "Error: Invalid response from Ollama API"
    except Exception as e:
        return f"Unexpected error: {str(e)}"

@app.route("/", methods=["GET", "POST"])
def index():
    response = None
    error = False
    last_prompt = ""
    
    if request.method == "POST":
        prompt = request.form.get("prompt", "").strip()
        last_prompt = prompt
        
        if prompt:
            response = query_ollama(prompt)
            if response.startswith("Error:"):
                error = True
        else:
            response = "Please enter a prompt."
            error = True
    
    return render_template_string(
        HTML, 
        response=response, 
        error=error, 
        last_prompt=last_prompt,
        ollama_url=OLLAMA_URL
    )

@app.route("/health")
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "ollama_url": OLLAMA_URL}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)