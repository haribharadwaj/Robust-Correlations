function [r,t,pval,CI] = Pearson(X,Y,varargin)

% Computes the Pearson correlation along with the alpha percent CI using
% the Z-transform which gives a relativey good probability coverage under
% normality assumptions. This returns in t(1) and pval(1) the same values
% as the Matlab corrcoef function. When H0 is rejected (say pval<0.05),
% it is reasonable to conclude that X and Y are dependent, but the nature of
% that dependence is unclear. If fact, in case of heteroscedasticity, even for
% rho = 0, H0 can be rejected because the t value relies on a wrong estimate
% of the variance, i.e. the test statisitics t, tests if X and Y are independent
% rather than testing if rho =0. Therefore, if pval is below the alpha level
% (H0 rejected) it should be compared to a robust t-test version that
% correct the covariance. Here, we return in t(2) and pval(2) such values
% using the HC4 estimator of the standard error (Godfrey, 2006). If that
% second p-value is also below alpha, CI are retuned using the standard
% z-transform. If pval is above alpha, but the robust estimate is below, the
% discrepency is likely due to heteroscedasticity and no good CI can be
% derived (returns NaN).
%
% FORMAT:  [r,t,p,CI] = Pearson(X,Y)
%          [r,t,p,CI] = Pearson(X,Y,'figure','on','alpha',0.05)
%
% INPUTS:  X and Y are 2 vectors or matrices (correlations are computed column-wise)
%                  if X and Y are a vector and a matrix, the vector is
%                  replicated to match the matrix size
%          options are 'figure', if X and Y are vectors, this is 'on' by
%                                default, if X and Y are matrices this 'off' by default
%                      'alpha', the alpha level to use for the confidence interval
%          If X and Y are matrices of size [n p], p correlations are computed and
%          the CI are adjusted at a level alpha/p (Bonferonni correction)
%
% OUTPUTS: r is the Pearson correlation
%          t are the t-values using the standard equation and using the hc4 variance estimate
%          pval are the p values corresponding to t-tests
%          CI is 1-alpha confidence interval (only if all(pvals<alpha) or all(pvals>alpha))
%
% If 'figure' is on, the data scatter plot is shown with the least
% square fit of the data and the confidence intervals from the r value. As a
% sanity check, the boostrapped correlations are also shown reporting the
% median of bootstrapped value.
%
% References:
% Fisher (1925). Statistical Methods for research workers. 1st Ed. Oliver and Boyd
% Godfrey (2006). Tests for regression models with heteroscedasticity of
%                 unknown form. Comp Stat & Data Analysis, 50, 2715-2733 
% Wilcox (2017). Introduction to Robust Estimation and Hypothesis Testing.
%                4th Ed. Acedemic Press
%
% Dr Cyril Pernet - University of Edinburgh
% -----------------------------------------
% Copyright (C) Corr_toolbox 2020

%% input checks
if nargin < 2
    error('two inputs requested');
else
    [X,Y] = check_corr_XY(X,Y);
end

% defaults
nboot              = 1000;
alphav             = 5/100;
heteroscedasticity = 'unspecified'; % undocumented, on/off forces to return a CI (never a NaN)
if size(X,2) == 1 % and therefore size(Y,2) = 1 as well
    figflag = 'on';
else
    figflag = 'off';
end

% check options
for v=1:2:size(varargin,2)
    if strcmpi(varargin{v},'figure')
        figflag = varargin{v+1};
    elseif strcmpi(varargin{v}(1:6),'hetero')
        heteroscedasticity = varargin{v+1};
        if ~strcmpi(varargin{v},'heteroscedasticity')
            fprintf('taking argument in ''%s'' as heteroscedasticity \n',varargin{v})
        end
    elseif strcmpi(varargin{v},'alpha')
        alphav = varargin{v+1};
        if ~isnumeric(alphav)
            alphav = str2double(alphav);
        end
    end
end

[n,p]  = size(X);
alphav = alphav./ p;

%% Compute
r = sum(detrend(X,'constant').*detrend(Y,'constant')) ./ ...
    (sum(detrend(X,'constant').^2).*sum(detrend(Y,'constant').^2)).^(1/2);

if nargout > 1 || strcmpi(figflag ,'on')
    zr                       = 0.5 * log((1+r)./(1-r));
    zalpha                   = icdf('Normal',alphav/2,0,1);
    t                        = r.*sqrt((n-2)./(1-r.^2));
    pval                     = 2*tcdf(-abs(t),n-2);
    S                        = 1/sqrt(n-3); % % Fisher 1925
    
    if ~strcmpi(heteroscedasticity,'off') % specifically ask not to do this       
        if p==1
            [t(2),pval(2),~,S_hc4] = get_hc4stats(r,zscore(X,0,1),zscore(Y,0,1));
        else
            [t(2,:),pval(2,:),~,S_hc4] = get_hc4stats(r,zscore(X,0,1),zscore(Y,0,1));
        end
    end
    
    for column = p:-1:1
        if all(pval(:,column)<alphav) || all(pval(:,column)>alphav) || strcmpi(heteroscedasticity,'off')
            CI(:,column) = tanh([zr(:,column)-abs(zalpha)*S ; zr(:,column)+abs(zalpha)*S]);
        else
            CI(:,column) = [NaN NaN]';
        end
    end
    
    %% undocumented - do a percentile t for the hc4 CI (kinda work for n>80)
    if strcmpi(heteroscedasticity,'on')
        
        if ~exist('boot_table','var')
            for B=nboot:-1:1
                % make a resampling boot_table with enough unique pairs
                go = 0;
                while go == 0
                    tmp = randi(n,n,1);
                    if length(unique(tmp))>=6
                        boot_table(:,B) = tmp;
                        go = 1;
                    end
                end
            end
        end
        
        % resample and compute
        ibot = round(alphav*nboot/2)+1;
        itop = nboot-ibot+2;
        for column = p:-1:1
            zX           = X(:,column);
            zX           = zscore(zX(boot_table),0,1);
            zY           = Y(:,column);
            zY           = zscore(zY(boot_table),0,1);
            [~,~,B,S]    = get_hc4stats(r(column),zX,zY); % all bootstraped betas and S
            v            = sort((B-r(column))./sqrt(S));
            CI(:,column) = [r(column)-v(itop)*sqrt(S_hc4(column)) r(column)-v(ibot)*sqrt(S_hc4(column))]';
        end
    end
end

%% figure
if strcmpi(figflag ,'on')
    if ~exist('boot_table','var')
        boot_table = randi(n,n,nboot);
    end
    for B=nboot:-1:1
        rb(B,:) = sum(detrend(X(boot_table(:,B),:),'constant').*detrend(Y(boot_table(:,B),:),'constant')) ./ ...
            (sum(detrend(X(boot_table(:,B),:),'constant').^2).*sum(detrend(Y(boot_table(:,B),:),'constant').^2)).^(1/2);
    end
end

if strcmpi(figflag ,'on')
    for f=1:length(r)
        figure('Name',sprintf('Pearson correlation X%g Y%g',f,f));
        set(gcf,'Color','w'); subplot(1,2,1);
        scatter(X(:,f),Y(:,f),100,'filled'); grid on; box on;
        xlabel('X','FontSize',12); ylabel('Y','FontSize',12);
        M = sprintf('r=%g \n %g%%CI [%.2f %.2f]',r(f),(1-alphav)*100,CI(1,f),CI(2,f));
        title(M,'FontSize',14); h=lsline; set(h,'Color','r','LineWidth',4);
        
        subplot(1,2,2); k = round(1 + log2(nboot));
        MV = histogram(rb(:,f),k); MV = max(MV.Values); grid on;
        title(sprintf('Bootstrapped correlations \n median=%g',median(rb)),'FontSize',14);
        xlabel('boot correlations','FontSize',12);ylabel('frequency','FontSize',12)
        axis tight; colormap([.4 .4 1]); box on;
        hold on; plot(median(rb),MV/2,'ko','LIneWidth',3)
        
        if all(~isnan(CI(1:2,f))) % plot CI
            plot(repmat(CI(1,f),MV,1),1:MV,'r','LineWidth',4);
            plot(repmat(CI(2,f),MV,1),1:MV,'r','LineWidth',4);
            subplot(1,2,1); hold on
            betas = pinv([X(:,f) ones(n,1)])*Y(:,f);
            transform = betas(1)/r(f);
            y1 = refline(CI(1,f)*transform,betas(2)); set(y1,'Color','r');
            y2 = refline(CI(2,f)*transform,betas(2)); set(y2,'Color','r');
            y1 = get(y1); y2 = get(y2);
            xpoints=[y1.XData(1):y1.XData(2),y2.XData(2):-1:y2.XData(1)];
            step1 = y1.YData(2)-y1.YData(1); step1 = step1 / (y1.XData(2)-y1.XData(1));
            step2 = y2.YData(2)-y2.YData(1); step2 = step2 / (y2.XData(2)-y2.XData(1));
            filled=[y1.YData(1):step1:y1.YData(2),y2.YData(2):-step2:y2.YData(1)];
            hold on; fillhandle=fill(xpoints,filled,[1 0 0]);
            set(fillhandle,'EdgeColor',[1 0 0],'FaceAlpha',0.2,'EdgeAlpha',0.8);%set edge color
        end
    end
end

