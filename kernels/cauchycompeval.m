function [vc vcp] = cauchycompeval(x,s,vb,side,o)
% CAUCHYCOMPEVAL.  Globally compensated barycentric int/ext Cauchy integral
%
% This is a spectrally-accurate close-evaluation scheme for Cauchy integrals.
%  It returns approximate values (and possibly first derivatives) of a function
%  either holomorphic inside of, or holomorphic and decaying outside of, a
%  closed curve, given a set of its values on nodes of a smooth global
%  quadrature rule for the curve (such as the periodic trapezoid rule).
%  This is done by approximating the Cauchy integral
%
%       v(x) =  +- (1/(2i.pi)) integral_Gamma v(y) / (x-y) dy,
%
%  where Gamma is the curve, the sign is + (for x interior) or - (exterior),
%  using special barycentric-type formulae which are accurate arbitrarily close
%  to the curve.
%
%  By default, for the value these formulae are (23) for interior and (27) for
%  exterior, from [hel08], before taking the real part.  The interior case
%  is originally due to [ioak]. For the derivative, the Schneider-Werner formula
%  (Prop 11 in [sw86]; see [berrut]) is used to get v' at the nodes, then since
%  v' is also holomorphic, it is evaluated using the same scheme as v.  This
%  "interpolate the derivative" suggestion of Trefethen (personal communication,
%  2014) contrasts [lsc2d] which "differentes the interpolant". The former gives
%  around 15 digits for values v, 14 digits for interior derivatives v', but
%  only 13 digits for exterior v'. (The other [lsc2d] scheme gives 14 digits
%  in the last case; see options below).  The paper [lsc2d] has key background,
%  and is helpful to understand [hel08] and [sw86].  This code replaces code
%  referred to in [lsc2d].
%
%  Instead of evaluation, the routine can also return the full M-by-N dense
%  matrix allowing evaluation for any vector of v at the nodes.
%
% Basic use:  v = cauchycompeval(x,s,vb,side)
%             [v vp] = cauchycompeval(x,s,vb,side)
%
% Inputs:
%  x = row or col vec of M targets, as points in complex plane
%  s = closed curve struct containing a set of vectors with N items each:
%       s.x  = smooth quadrature nodes on curve, as points in complex plane
%       s.w  = smooth weights for arc-length integrals (scalar "speed weights")
%       s.nx = unit normals at nodes (unit complex numbers)
%  vb = row or col vec of N boundary values of holomorphic function v
%  side = 'i' or 'e' specifies if all targets interior or exterior to curve.
%
% Outputs:
%  v  = row vec approximating the homolorphic function v at the M targets
%  vp = (optional) row vec of complex first derivative v' at the M targets
%
% Without input arguments, a self-test is done outputting errors at various
%  distances from the curve for a fixed N. (Needs setupquad.m)
%
% Notes:
% 1) For accuracy, the smooth quadrature must be accurate for the boundary data
%  vb, and it must come from a holomorphic function (be in the right Hardy
%  space).
% 2) For the exterior case, v must vanish at infinity.
% 3) The algorithm is O(NM) in time. In order to vectorize in both sources and
%  targets, it is also O(NM) in memory - using loops this could of course be
%  reduced to O(N+M). If RAM is a limitation, targets should be blocked into
%  reasonable numbers and a separate call done for each).
%
% If vb is empty, the outputs v and vp are instead the dense evaluation
%  matrices, which costs O(N^2M) time.
%
% Advanced use: [vc vcp] = cauchycompeval(x,s,vb,side,opts) allows control of
% options such as
%   opts.delta : switches to a different [lsc2d] scheme for v', which is
%                non-barycentric for distances beyond delta, but O(N) slower
%                for distances closer than delta. This achieves around 1 extra
%                digit for v' in the exterior case. I recommend delta=1e-2.
%                For this scheme, s must have the following extra field:
%                    s.a  = a point in the "deep" interior of curve (far from
%                           the boundary)
%                delta=0 never uses the barycentric form for v'.
%
% References:
%
%  [sw86]  C. Schneider and W. Werner, Some new aspects of rational
%          interpolation, Math. Comp., 47 (1986), pp. 285–299
%
%  [ioak]  N. I. Ioakimidis, K. E. Papadakis, and E. A. Perdios, Numerical
%          evaluation of analytic functions by Cauchy’s theorem, BIT Numer.
%          Math., 31 (1991), pp. 276–285
%
%  [berrut] J.-P. Berrut and L. N. Trefethen, Barycentric Lagrange
%          interpolation, SIAM Review, 46 (2004), pp. 501-517
%
%  [hel08] J. Helsing and R. Ojala, On the evaluation of layer potentials close
%          to their sources, J. Comput. Phys., 227 (2008), pp. 2899–292
%
%  [lsc2d] Spectrally-accurate quadratures for evaluation of layer potentials
%          close to the boundary for the 2D Stokes and Laplace equations,
%          A. H. Barnett, B. Wu, and S. Veerapaneni, SIAM J. Sci. Comput.,
%          37(4), B519-B542 (2015)   https://arxiv.org/abs/1410.2187
%
% See also: tests/FIG_CAUCHYCOMPEVAL, SETUPQUAD.
%
% Todo: * allow mixed interior/exterior targets, and/or auto-detect this.

% (c) Alex Barnett 2016
% based on code from 10/22/13.

if nargin<1, test_cauchycompeval; return; end
if nargin<5, o = []; end
if isfield(o,'delta')
  if ~isfield(s,'a'), error('s.a interior pt needed to use lsc2d version'); end
  if nargout==1, vc = cauchycompeval_lsc2d(x,s,vb,side,o);
  else, [vc vcp] = cauchycompeval_lsc2d(x,s,vb,side,o); end
  return
end

cw = s.cw;                    % complex speed weights
N = numel(s.x); M = numel(x);

% Do bary interp for value outputs. note sum along 1-axis faster than 2-axis...
comp = repmat(cw(:), [1 M]) ./ (repmat(s.x(:),[1 M]) - repmat(x(:).',[N 1]));
I0 = sum(repmat(vb(:),[1 M]).*comp); J0 = sum(comp);  % Ioakimidis notation
if side=='e', J0 = J0-2i*pi; end                      % Helsing exterior form
vc = I0./J0;                                          % bary form
[jj ii] = ind2sub(size(comp),find(~isfinite(comp)));  % node-targ coincidences
for l=1:numel(jj), vc(ii(l)) = vb(jj(l)); end   % replace each hit w/ corresp vb

if nargout>1     % 1st deriv also wanted... Trefethen idea first get v' @ nodes
  vbp = 0*vb;    % prealloc v' @ nodes
  if side=='i'
    for j=1:N
      notj = [1:j-1, j+1:N];  % std Schneider-Werner form for deriv @ node...
      vbp(j) = -sum(cw(notj).*(vb(j)-vb(notj))./(s.x(j)-s.x(notj)))/cw(j);
    end
  else
    for j=1:N
      notj = [1:j-1, j+1:N];  % exterior version of S-W form derived 6/12/16...
      vbp(j) = (-sum(cw(notj).*(vb(j)-vb(notj))./(s.x(j)-s.x(notj)))-2i*pi*vb(j))/cw(j);
      %abs(vbp(j) / (2i*pi*vb(j)/cw(j))) % shows 2.5 digits of cancellation, bad
    end
  end
  % now again do bary interp of v' using its value vbp at nodes...
  I0 = sum(repmat(vbp(:),[1 M]).*comp); J0 = sum(comp);
  if side=='e', J0 = J0-2i*pi; end                    % Helsing exterior form
  vcp = I0./J0;                                       % bary form
  for l=1:numel(jj), vcp(ii(l)) = vbp(jj(l)); end     % replace each hit w/ vbp
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [vc, vcp] = cauchycompeval_lsc2d(x,s,vb,side,o)
% Variant of the above, used in the [lsc2d] paper.
%
% The only new input needed is s.a, an interior point far from the boundary.
%
% The algorithm is that of Ioakimidis et al BIT 1991 for interior, and,
% for the exterior, a modified version using 1/(z-a) in place of the function 1.
% For the derivative, the formula is mathematically the derivative of the
% barycentric formula of Schneider-Werner 1986 described in Berrut et al 2005,
% but using the complex quadrature weights instead of the barycentric weights.
% However, since this derivative is not itself a true barycentric form, a hack
% is needed to compute the difference v_j-v(x) in a form where roundoff error
% cancels correctly. The exterior case is slightly more intricate. When
% a target coincides with a node j, the true value v_j (or Schneider-Werner
% formula for v'(x_j)) is used.
%
% Alex Barnett 10/22/13 based on cauchycompevalint, pole code in lapDevalclose.m
% 10/23/13 node-targ coincidences fixed, exterior true barycentric discovered.

% todo: check v' ext at the node (S-W form), seems to be wrong.

if nargin<5, o = []; end
if size(vb,2)>1              % matrix versions
  if nargout==1, vc = cauchycompmat_lsc2d(x,s,vb,side,o);
  else, [vc vcp] = cauchycompmat_lsc2d(x,s,vb,side,o); end
  return
end
if ~isfield(o,'delta'), o.delta = 1e-2; end  % currently you have to set by hand
% dist param where $O(N^2.M) deriv bary form switched on.
% Roughly deriv errors are then limited to emach/mindist
% The only reason to decrease mindist is if lots of v close
% nodes on the curve with lots of close target points.

cw = s.cw;                    % complex speed weights
N = numel(s.x); M = numel(x);

if nargout==1  % no deriv wanted... (note sum along 1-axis faster than 2-axis)
  comp = repmat(cw(:), [1 M]) ./ (repmat(s.x(:),[1 M]) - repmat(x(:).',[N 1]));
  if side=='e', pcomp = comp .* repmat(1./(s.x(:)-s.a), [1 M]);
  else pcomp = comp; end  % pcomp are weights and bary poles appearing in J0
  I0 = sum(repmat(vb(:),[1 M]).*comp); J0 = sum(pcomp); % Ioakimidis notation
  vc = I0./J0;                        % bary form
  if side=='e', vc = vc./(x(:).'-s.a); end         % correct w/ pole
  [jj ii] = ind2sub(size(comp),find(~isfinite(comp))); % node-targ coincidences
  for l=1:numel(jj), vc(ii(l)) = vb(jj(l)); end % replace each hit w/ corresp vb
  
else           % 1st deriv wanted...
  invd = 1./(repmat(s.x(:),[1 M]) - repmat(x(:).',[N 1])); % 1/displacement mat
  comp = repmat(cw(:), [1 M]) .* invd;
  if side=='e', pcomp = comp .* repmat(1./(s.x(:)-s.a), [1 M]);
  else pcomp = comp; end  % pcomp are weights and bary poles appearing in J0
  I0 = sum(repmat(vb(:),[1 M]).*comp); J0 = sum(pcomp);
  if side=='e', prefac = 1./(x(:).'- s.a); else prefac = 1; end
  vc = prefac .* I0./J0;                        % bary form (poss overall pole)
  dv = repmat(vb(:),[1 M]) - repmat(vc(:).',[N 1]); % v value diff mat
  [jj ii] = ind2sub(size(invd),find(abs(invd) > 1/o.delta)); % bad pairs indices
  if side=='e' % exterior:
    for l=1:numel(jj), j=jj(l); i=ii(l); % loop over node-targ pairs too close
      p = sum(comp(:,i).*(vb(j)./(s.x(:)-s.a)-vb(:)./(s.x(j)-s.a))) / sum(pcomp(:,i)); % p is v_j - (x-a)/(yj-a)*v(x) for x=i'th target
      dv(j,i) = prefac(i) * ((s.x(j)-s.a)*p + (x(i)-s.x(j))*vb(j));
    end % pole-corrected for dv, gives bary stability for close node-targ pairs
  else  % interior:
    for l=1:numel(jj), j=jj(l); i=ii(l); % loop over node-targ pairs too close
      dv(j,i) = sum(comp(:,i).*(vb(j)-vb(:))) / sum(pcomp(:,i));
    end % bary for dv, gives bary stability for close node-targ pairs
  end
  vcp = prefac .* sum(dv.*comp.*invd) ./ J0; % bary form for deriv
  [jj ii] = ind2sub(size(comp),find(~isfinite(comp))); % node-targ coincidences
  for l=1:numel(jj), j=jj(l); i=ii(l); % loop over hitting node-targ pairs
    vc(i) = vb(j);                     % replace each hit w/ corresp vb
    notj = [1:j-1, j+1:N];             % Schneider-Werner form for deriv @ node:
    vcp(i) = -sum(cw(notj).*(vb(j)-vb(notj))./(s.x(j)-s.x(notj)))/cw(j);
  end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [vc vcp] = cauchycompmat_lsc2d(x,s,vb,side,o)
% Multiple vb-vector version of cauchycompeval_lsc2d, written by Gary Marple
% and Bowei Wu, 2014-2015. This can be called with eye(N) to fill the evaluation
% matrix (note that each column is not a holomorphic function, but be linearity
% when summed they give the right answer). When sent a single column vector
% for vb, this duplicates the action of cauchycompeval_lsc2d.
% Notes by Barnett 6/12/16

% todo: check v' ext at the node (S-W form), seems to be wrong.

if nargin<5, o = []; end
if ~isfield(o,'delta'), o.delta = 1e-2; end
% dist param where $O(N^2.M) deriv bary form switched on.
% Roughly deriv errors are then limited to emach/mindist
% The only reason to decrease mindist is if lots of v close
% nodes on the curve with lots of close target points.

cw = s.cw;                    % complex speed weights
N = numel(s.x); M = numel(x);
n=size(vb,2);                  % # vb vectors

if nargout==1  % no deriv wanted... (note sum along 1-axis faster than 2-axis)
  comp = repmat(cw(:), [1 M]) ./ (repmat(s.x(:),[1 M]) - repmat(x(:).',[N 1]));
  if side=='e', pcomp = comp .* repmat(1./(s.x(:)-s.a), [1 M]);
  else pcomp = comp; end  % pcomp are weights and bary poles appearing in J0
  %I0 = sum(repmat(vb(:),[1 M]).*comp); 
  I0 = permute(sum(repmat(permute(vb,[1 3 2]),[1 M 1]).*repmat(comp,[1 1 n]),1),[3 2 1]);
  J0 = sum(pcomp); % Ioakimidis notation
  vc = I0./(ones(n,1)*J0);                        % bary form
  if side=='e', vc = vc./(ones(n,1)*(x(:).'-s.a)); end         % correct w/ pole
  [jj ii] = ind2sub(size(comp),find(~isfinite(comp))); % node-targ coincidences
  for l=1:numel(jj), vc(:,ii(l)) = vb(jj(l),:).'; end % replace each hit w/ corresp vb

else           % 1st deriv wanted...
  invd = 1./(repmat(s.x(:),[1 M]) - repmat(x(:).',[N 1])); % 1/displacement mat
  comp = repmat(cw(:), [1 M]) .* invd;
  if side=='e', pcomp = comp .* repmat(1./(s.x(:)-s.a), [1 M]);
  else pcomp = comp; end  % pcomp are weights and bary poles appearing in J0
  %I0 = sum(repmat(vb(:),[1 M]).*comp);
  I0 = permute(sum(repmat(permute(vb,[1 3 2]),[1 M 1]).*repmat(comp,[1 1 n]),1),[3 2 1]);
  J0 = sum(pcomp);
  if side=='e', prefac = 1./(x(:).'- s.a); else prefac = ones(1,M); end
  vc = (ones(n,1)*prefac) .* I0./(ones(n,1)*J0);                        % bary form (poss overall pole)
  %dv = repmat(vb(:),[1 M]) - repmat(vc(:).',[N 1]); % v value diff mat
    dv = repmat(permute(vb,[1 3 2]),[1 M 1]) - repmat(permute(vc,[3 2 1]),[N 1 1]); % v value diff mat
  [jj ii] = ind2sub(size(invd),find(abs(invd) > 1/o.delta)); % bad pairs indices
  if side=='e' % exterior:
    for l=1:numel(jj), j=jj(l); i=ii(l); % loop over node-targ pairs too close
      p = sum((comp(:,i)*ones(1,n)).*((ones(N,1)*vb(j,:))./(s.x(:)*ones(1,n)-s.a)-vb/(s.x(j)-s.a)),1) / sum(pcomp(:,i)); % p is v_j - (x-a)/(yj-a)*v(x) for x=i'th target
      dv(j,i,:) = prefac(i) * ((s.x(j)-s.a)*p + (x(i)-s.x(j))*vb(j,:));
    end % pole-corrected for dv, gives bary stability for close node-targ pairs
  else  % interior:
    for l=1:numel(jj), j=jj(l); i=ii(l); % loop over node-targ pairs too close
      dv(j,i,:) = sum((comp(:,i)*ones(1,n)).*(ones(size(vb,1),1)*vb(j,:)-vb),1) / sum(pcomp(:,i));
    end % bary for dv, gives bary stability for close node-targ pairs
  end
  % This is faster, but gives rounding errors when compared to the original
  % cauchycompeval.
  vcp = (ones(n,1)*(prefac./ J0)).* permute(sum(dv.*repmat(comp.*invd,[1 1 n]),1),[3 2 1]) ; % bary form for deriv
  
  % This vectorized form is slower, but does not give rounding errors.
  %vcp = (ones(n,1)*prefac).* permute(sum(dv.*repmat(comp,[1 1 n]).*repmat(invd,[1 1 n]),1),[3 2 1])./(ones(n,1)*J0) ; % bary form for deriv
  
  [jj ii] = ind2sub(size(comp),find(~isfinite(comp))); % node-targ coincidences
  for l=1:numel(jj), j=jj(l); i=ii(l); % loop over hitting node-targ pairs
    vc(:,i) = vb(j,:).';                     % replace each hit w/ corresp vb
    notj = [1:j-1, j+1:N];             % Schneider-Werner form for deriv @ node:
    vcp(i,:) = -sum((cw(notj)*ones(1,n)).*((ones(N-1,1)*vb(j,:))-vb(notj,:))./((s.x(j)-s.x(notj))*ones(1,n)),1)/cw(j);
  end
end


%%%%%%%%%%%%%%%%%%%%%%%%%
function test_cauchycompeval          % only test eval, not the matrix version
a = .3; w = 5;         % smooth wobbly radial shape params
N = 200;               % must be multiple of 4
t = (1:N)/N*2*pi; s.x = (1 + a*cos(w*t)).*exp(1i*t);
s = setupquad(s);

format short g
for side = 'ie'
  a = 1.1+1i; if side=='e', a = .1+.5i; end % pole, dist 0.5 from G, .33 for ext
  v = @(z) 1./(z-a); vp = @(z) -1./(z-a).^2;   % used in paper

  z0 = s.x(N/4);
  ds = logspace(0,-18,10)*(.1-1i); % displacements
  if side=='e', ds = -ds; end % flip to outside
  z = z0 + ds; z(end) = z0; % ray of pts heading to a node, w/ last hit exactly
  vz = v(z); vpz = vp(z); M = numel(z);
  
  d = repmat(s.x(:),[1 M])-repmat(z(:).',[N 1]); % displ mat
  %vc = sum(repmat(v(s.x).*s.cw,[1 M])./d,1)/(2i*pi); % naive Cauchy (so bad!)
  [vc vcp] = cauchycompeval(z,s,v(s.x),side);    % current version
  %s.a=0; [vc vcp] = cauchycompeval(z,s,v(s.x),side,struct('delta',.01)); % oldbary alg, 0.5-1 digit better for v' ext, except at the node itself.
  err = abs(vc - vz); errp = abs(vcp - vpz);
  disp(['side ' side ':  dist        v err       v'' err'])
  [abs(imag(ds))' err' errp']
end

%figure; plot(s.x,'k.-'); hold on; plot(z,'+-'); axis equal