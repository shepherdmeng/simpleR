function [fX, dfX] = gpw03lik(X, input, t, dflag);

global invQ logdetQ; % used in gpw03fastlik to avoid recomputation

% gpw03lik: Compute minus log likelihood and its derivatives with respect to
% parameters for the warped Gaussian process with neural net covariance
%
% Based on code for GPs by Carl Edward Rasmussen (gp03lik)
% 
% X      is the vector of parameters of length D+3+3*num, where num is
%        the number of tanh functions in the warp (see warp):
%
% X = [ log(S_1)
%       log(S_2) 
%        .
%       log(S_D+1)
%       log(v1)
%       log(v0) 
%       a
%       b
%       c ]
%
% S,v    are the hyperparameters of the covariance (see gp01lik)
% a,b,c  are vectors of warping parameters of length num (see warp)
% 
% input  is an (n x D) array of data
% t      is a (n x 1) vector of target values
% dflag  == 'g' outputs only gradients; dflag = 'f' outputs only
%        function values
% 
% Use in conjunction with gradient based minimizer such as Carl
% Edward Rasmussen's "minimize":
%
% [X, fX, i] = minimize(X, 'gpw03lik', length, input, t, dflag)

if nargin < 4, dflag = 'default'; end
[n, D] = size(input);       % number of examples and dimension of input space
num = (length(X) - D - 3)/3; % number of tanh functions in warp
expX = exp(X);

% prior means and variances in hyperparameters
% alter these to do MAP rather than ML optimization
sX = repmat(1e15,length(X),1);
muX = zeros(size(X));
%sX(D+4+num:D+3+2*num) = 4; % may want to stop warp becoming too steep

% first, we write out the covariance matrix Q

Q = repmat(expX(1:D)',n,1).*input*input';
Z = (expX(D+1)+Q)./(sqrt(1+expX(D+1)+diag(Q))*sqrt(1+expX(D+1)+diag(Q)'));
Q = expX(D+2)*asin(Z) + expX(D+3)*eye(n);

for i = 1:num % the parameters for warping function
    ea(i,1) = expX(D+3+i); eb(i,1) = expX(D+3+num+i);
    c(i,1) = X(D+3+2*num+i);
end

z = warp(t,ea,eb,c);   % warp target values onto latent variable z

invQ = inv(Q);
invQz = invQ*z;
w = ones(n,1);
for i = 1:num % various useful constructs
    s{i} = eb(i)*(t + c(i));
    r{i} = tanh(s{i});
    y{i} = 1 - r{i}.^2;
    w = w + ea(i)*eb(i).*y{i};
end

% calculate minus log likelihood ...

if dflag == 'default' | dflag == 'f'
  logdetQ = 2*sum(log(diag(chol(Q)))); % don't compute det(Q) directly
  jacob = sum(log(w)); % jacobian term 
  fX = 0.5*logdetQ + 0.5*z'*invQz + 0.5*n*log(2*pi) - jacob + ...
       0.5*sum(((X-muX).^2)./sX);% + log(2*pi*sX));
else
   fX = [];
end

% ... and its partial derivatives

if dflag == 'default' | dflag == 'g'
  dfX = zeros(D+3+3*num,1);  % set the size of the derivative
                             % vector

% derivatives wrt hyperparameters
Q = repmat(expX(1:D)',n,1).*input*input';
for d = 1:D
  v = input(:,d).^2./(1+expX(D+1)+diag(Q));
  V = (input(:,d)*input(:,d)'./(sqrt(1+expX(D+1)+diag(Q))*sqrt(1+expX(D+1)+diag(Q)'))-Z.*(repmat(v,1,n)+repmat(v',n,1))/2)./sqrt(1-Z.^2); 
  dfX(d) = expX(D+2)*expX(d)*(sum(sum(invQ.*V)) - invQz'*V*invQz)/2;
end 

v = 1./(1+expX(D+1)+diag(Q));
V = (1./(sqrt(1+expX(D+1)+diag(Q))*sqrt(1+expX(D+1)+diag(Q)'))-Z.*(repmat(v,1,n)+repmat(v',n,1))/2)./sqrt(1-Z.^2);
dfX(D+1) = expX(D+2)*expX(D+1)*(sum(sum(invQ.*V)) - invQz'*V*invQz)/2;

V = asin(Z);
dfX(D+2) = expX(D+2)*(sum(sum(invQ.*V)) - invQz'*V*invQz)/2;
dfX(D+3) = expX(D+3)*(trace(invQ) - invQz'*invQz)/2;

for i = 1:num % derivatives wrt warping parameters
    dfX(D+3+i) = ea(i)*(r{i}'*invQz  - sum(eb(i).*y{i}./w));
    dfX(D+3+num+i) = eb(i)*((ea(i)*(t+c(i)).*y{i})'*invQz - sum((ea(i).*y{i} - ea(i)*eb(i)*2.*y{i}.*r{i}.*(t+c(i)))./w));
    dfX(D+3+2*num+i) = (ea(i)*eb(i).*y{i})'*invQz + sum(ea(i)*eb(i)^2*2.*y{i}.*r{i}./w);
end
for d = 1:length(X)
    dfX(d) = dfX(d) + (X(d)-muX(d))/sX(d);
end			     
			     
else
  dfX = [];
end
