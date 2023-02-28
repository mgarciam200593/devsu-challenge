from flask import Flask, jsonify, request

app = Flask(__name__)

@app.route('/DevOps', methods=['POST'])
def post_message():
    data = request.json
    return jsonify({"message": "Hello " + data['to'] + " your message will be send"})

if __name__ == '__main__':
    app.run(host='0.0.0.0')