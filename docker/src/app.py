from flask import Flask, jsonify, request

app = Flask(__name__)

def msg_response(data):
    res = {"message": "Hello " + data['to'] + " your message will be send"}
    return res


@app.route('/healthz', methods=['GET'])
def health_check():
    return "Health Check!!"

@app.route('/DevOps', methods=['POST'])
def post_message():
    req_data = request.json
    return jsonify(msg_response(req_data))

@app.errorhandler(405)
def method_not_allowed():
    return 'ERROR'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
    