firebaseBaseUrl = "https://ew202-interactive-default-rtdb.firebaseio.com";
endpoint = firebaseBaseUrl + "/submissions.json";


for i=1:3
  data = webread(endpoint);
  disp(data);
  pause(1);
end