// Copyright (c) 2020 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/test;
import ballerina/lang.'transaction as trx;

listener http:Listener serviceTestEP = new(9090);
FooClient stClient = new(9090);

@http:ServiceConfig {}
service /echo on serviceTestEP {

    @http:ResourceConfig {
    }
    transactional resource function get message(http:Caller caller, http:Request req) {
        http:Response res = new;
        checkpanic caller->respond(res);
    }
}

public client class FooClient {

    public http:Client httpClient;

    public function init(int port) {
        self.httpClient = checkpanic new("http://localhost:9090");
    }

    transactional remote function foo() returns @tainted any|error {
        return self.httpClient->get("/echo/message");
    }

}

@test:Config {}
function testTransactionalServices() {
    transaction {
        var response = stClient->foo();
        var x = checkpanic commit;
        if (response is http:Response) {
            test:assertEquals(response.statusCode, 200, msg = "Found expected output");
        } else if (response is error) {
            test:assertFail(msg = "Found unexpected output type: " + response.message());
        }
    }
}

isolated string handlerClientOutput = "start";

var onRollbackFuncInsideClient = isolated function(trx:Info? info, error? cause, boolean willTry) {
                         lock {
                             handlerClientOutput += " -> trxAborted inside client";
                         }
                     };

var onCommitFuncInsideClient = isolated function(trx:Info? info) {
                        lock {
                            handlerClientOutput += " -> trxCommited inside client";
                        }
                    };

public client class BarClient {

    public http:Client httpClient;

    public function init(int port) {
        self.httpClient = checkpanic new("http://localhost:9090");
    }

    transactional remote function foo() returns @tainted any|error {
        trx:onCommit(onCommitFuncInsideClient);
        trx:onRollback(onRollbackFuncInsideClient);
        return self.httpClient->get("/echo/message");
    }
}

BarClient barClient = new(9090);

@test:Config {}
function testHandlersWithinTransactionalClient() {
    transaction {
        lock {
            handlerClientOutput += " -> within trx block";
        }
        var response = barClient->foo();
        var x = checkpanic commit;
        if (response is http:Response) {
            test:assertEquals(response.statusCode, 200, msg = "Found expected output");
        } else if (response is error) {
            test:assertFail(msg = "Found unexpected output type: " + response.message());
        }
        lock {
                handlerClientOutput += " -> trx ended";
        }
    }
    lock {
        test:assertEquals(handlerClientOutput, "start -> within trx block -> trxCommited inside client -> trx ended");
    }
}